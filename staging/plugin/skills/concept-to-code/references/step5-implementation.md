
#### Recovery-readiness pre-flight (ADR-0050, before any dispatch)

Five assertions, run once, at the very top of Step 5 — before dispatch-mode selection, before the Smoke test gate below (which itself dispatches a workflow coder), and before the tester stage ADR-0049 introduced further down. At Step 5 entry the tree must already be clean, so that everything the tester dirties afterward is provably Step 5's own doing. (5.0.4b, added by ADR-0159, is the fifth; ADR-0050's original four are unchanged.)

**ADR-0050 §D4 — the reconciliation, updated by ADR-0068 §D6.** This pre-flight guards entry to Step 5, before anything in Step 5 has executed: a dirty tree here is uncommitted human work of unknown provenance, so it refuses to dispatch. ADR-0049 §D2's dirty-tree condition, which used to guard each coder dispatch *inside* Step 5 by tolerating a tree the tester stage had deliberately left dirty and dropping isolation to a second, worktree-less mode, is retired: the tester now runs in its own worktree and its output is committed and merged into the feature branch before the coder's worktree is created (ADR-0068 §D6), so the condition it tested for cannot arise. The two conditions were sequential, not contradictory, while both existed; the surviving invariant is narrower and is what replaces them both: at Step 5 entry the tree is clean, and every stage's output is committed and merged before the next stage's worktree is created.

**Step 5.0.1 — Working tree clean, APART FROM THE MANIFEST (ADR-0050 §D2, amended by issue #239).**

<!-- fence-contract: c2c-step5-preflight-dirty-classify -->
```bash
# ADR-0133 §D1 (issue #394): everything between the two FENCE_BASH lines runs under BASH, not under
# the host shell, which is zsh here and differs from bash on word splitting, unmatched globs and
# `echo` escapes. `export` forwards this body's caller-bound free variables across the new process
# boundary; a plain shell variable does not survive it. The nested `DIRTY_EOF` here-document below
# is unaffected — the outer delimiter is matched only by a line reading exactly FENCE_BASH, so the
# inner one reaches bash intact. The terminator sits at COLUMN 0 on purpose: an indented one is
# swallowed into the here-document and destroys this fence's exit code silently, which here would
# read as a clean tree. Do not tidy it.
export MANIFEST SPEC ADR PLAN CLAUDE_PLUGIN_ROOT
bash <<'FENCE_BASH'
# Free variables, bound by the orchestrator before this block runs:
#   MANIFEST        absolute path to the manifest (the value manifest-init.sh printed)
#   SPEC ADR PLAN   absolute paths from manifest.artifacts.*; ADR/PLAN may be empty on Express
# Exit contract: 0 = clean, proceed to 5.0.2 · 1 = refuse to dispatch · 3 = the check DID NOT RUN.
# The third exists for the same reason it does in spec-coverage.sh and plan-tasks.sh: a checker
# that could not run must not be readable as a checker that found nothing.
_top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "PREFLIGHT_NOREPO"; exit 3; }
[ -n "${MANIFEST:-}" ] || { echo "PREFLIGHT_NOMANIFEST"; exit 3; }
# repo-rel-path.sh ASKS GIT for the repo-relative path. It does not compare strings, and that is
# the whole point: every string form of this comparison has a normalisation it does not perform.
#
# The first draft compared `git rev-parse --show-toplevel` (resolved) against the caller's path
# (not), so `rel()` shortened nothing and EVERY artifact classified as OTHER — including the
# manifest, which made the exemption silently inert. #239 fixed that by resolving both sides with
# `cd … && pwd -P`. That closed the symlink half only: **`pwd -P` resolves symlinks, it does not
# normalise case.** APFS is case-insensitive and case-preserving, so `cd /Users/x/developer/…`
# succeeds and reports the casing you traversed, while git reports the casing it recorded — the
# prefix match failed again, on the same file, for a different reason, and the exemption was inert
# on every run from a differently-cased CWD (issue #344, found by running the chain, twice over).
#
# Deriving the prefix from git removes the comparison rather than correcting it, so there is no
# third normalisation left to miss. The `-ef` guard is device+inode identity — "is this the same
# directory" answered without going back through a string compare, which is the trap being removed.
# It is what keeps an artifact living in a DIFFERENT repository from being handed that repository's
# prefix and silently exempted. Pinned by `recovery-preflight.test.sh` RJ9 (symlink), RJ13/RJ13b
# (case) and RJ14 (foreign repo) through this fence, and by its RRP section directly.
#
# The logic lives in repo-rel-path.sh rather than in a function here because this fence is
# RENDERED before the model executes it, and the renderer substitutes the skill's own invocation
# arguments into the parameter that function read — so what ran was a normalisation whose input
# had been replaced by an unrelated word, reintroducing #239 at render time inside the very block
# written to fix it (issue #385, ADR-0132 §D1). A file is never rendered. Resolved ONCE here,
# above the first of the four calls below; an unresolved helper is the check DID NOT RUN, never a
# clean tree.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] \
   && [ -f "$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/repo-rel-path.sh" ]; then
  _rrp="$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/repo-rel-path.sh"
elif [ -f "$HOME/.claude/skills/concept-to-code/scripts/repo-rel-path.sh" ]; then
  _rrp="$HOME/.claude/skills/concept-to-code/scripts/repo-rel-path.sh"
else
  echo "PREFLIGHT_NOHELPER"
  echo "  repo-rel-path.sh is not deployed. Run: bash <repo>/staging/sync-to-claude.sh --apply"
  exit 3
fi

# The manifest leaves the dirty set BEFORE anything is classified. Do not put it back — see the
# paragraph below this fence for why, and read #239 before deciding the exemption looks careless.
DIRTY=$(git status --porcelain | sed 's/^...//' | grep -vxF "$(bash "$_rrp" "$_top" "$MANIFEST")" || true)
[ -n "$DIRTY" ] || { echo "PREFLIGHT_CLEAN"; exit 0; }

SPEC_REL=$(bash "$_rrp" "$_top" "${SPEC:-}")
ADR_REL=$(bash "$_rrp" "$_top" "${ADR:-}")
PLAN_REL=$(bash "$_rrp" "$_top" "${PLAN:-}")
CHAIN=""; OTHER=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in
    "$SPEC_REL"|"$ADR_REL"|"$PLAN_REL"|CLAUDE.md) CHAIN="$CHAIN$f " ;;
    *) OTHER="$OTHER$f " ;;
  esac
done <<DIRTY_EOF
$DIRTY
DIRTY_EOF

if [ -n "$CHAIN" ] && [ -n "$OTHER" ]; then echo "PREFLIGHT_BOTH chain: $CHAIN| other: $OTHER"; exit 1
elif [ -n "$CHAIN" ]; then echo "PREFLIGHT_CHAIN $CHAIN"; exit 1
else echo "PREFLIGHT_OTHER $OTHER"; exit 1
fi
FENCE_BASH
```

**Why the manifest is exempt, and why removing the exemption breaks every run (issue #239).** The
chain writes the manifest at every state change, and two of those writes land between Gate 4.0's
commit and this assertion: `manifest-set-flag.sh <m> autopilot true` and `manifest-transition.sh <m> <!-- path-rule-exempt: names which two manifest writes land here rather than instructing; one marker covers both occurrences on this line -->
ready_for_implementation`. On the fresh-session branch it is worse — Form B resume step 3 updates
`session_boundary.resumed_at` unconditionally, after any commit the old session could have made, so
no ordering avoids it. Then 5.0.3 below writes `recovery_baseline_sha` into the same file **on
purpose**, three assertions later. "The working tree is clean" and "the manifest is written at every
state change" are flatly incompatible requirements on the same file; the pre-flight asserted one
while the state machine implemented the other, so this assertion had never been satisfied by a real
chain run. ADR-0050 §D2's purpose survives intact: it refuses on work of **unknown provenance**, and
the manifest's provenance is the most known thing in the repository, since the chain is its only
writer. `SPEC.md`, the ADR and the plan stay in the set, so the check this assertion exists for is
unchanged. Reordering Gate 4.0 was considered and rejected: it fixes the in-session branch and
cannot fix the resume branch at all.

**The exemption is bounded by a validity check, not by trust.** Excluding the file from the dirty
set would otherwise let a hand-edited manifest through — and ADR-0075 measured hand-edits as real,
not hypothetical. So run the validator that actually applies to that file, on both Gate 4 branches
(Form B resume already does this at its step 1; the in-session branch never did):
```bash
bash ~/.claude/skills/concept-to-code/scripts/manifest-validate.sh "<manifest>"
```
Non-zero → refuse to dispatch and print the validator's own stderr verbatim. What is exempt is the
manifest's **dirtiness**, never its **content**.

**Remediation, keyed to the token the fence printed:**

- **`PREFLIGHT_CHAIN`** → a chain artifact is uncommitted: the producer did not run, or ran and was
  declined. Print: "Recovery-readiness pre-flight: the chain's own planning artifacts are
  uncommitted. Gate 4.0 should have committed them. Run `/skill commit '<topic> — planning
  artifacts' --no-pr`, then re-invoke Step 5." **Never advise `git stash` here**: `-u` would stash
  `SPEC.md`, the ADR and the plan, which are exactly what the coder and tester dispatches read,
  producing a Step 5 that runs against missing inputs. Until ADR-0071 this was the printed advice,
  and it was wrong on the only path that ever reached it.
- **`PREFLIGHT_OTHER`** → this is the deliberately-dirty resume ADR-0050 §D2 negative consequence 2
  describes. Print: "Recovery-readiness pre-flight: working tree has uncommitted changes unrelated
  to the chain. Run `git stash push -u -m 'c2c-step5-preflight'` (or commit them) and re-invoke
  Step 5."
- **`PREFLIGHT_BOTH`** → prescribe the commit first, then the stash, in that order, and say why:
  committing the artifacts is what makes the stash safe.
- **`PREFLIGHT_NOREPO` / `PREFLIGHT_NOMANIFEST` / `PREFLIGHT_NOHELPER` (exit 3)** → the check did
  not run. Refuse to dispatch and say so in those words. Do not report it as a clean tree.
  `PREFLIGHT_NOHELPER` means `repo-rel-path.sh` is not deployed, and it prints its own remedy: run
  `bash <repo>/staging/sync-to-claude.sh --apply`, then re-invoke Step 5. This gate is worse than
  inert until that sync — an un-synced machine refuses **every** Step 5 rather than mis-classifying
  one, which is the right direction and still a new failure (ADR-0132 §Consequences).

Known limits, stated rather than discovered later: the fence reads porcelain v1, so a **renamed**
chain artifact arrives as `old -> new` and classifies as `OTHER`, and a path containing a space or
a quote is quoted by git and will not match. Neither shape occurs for the four artifacts this
classifies, and `*.bak` is gitignored, so 5.0.3's `sed -i.bak` debris is invisible to both this
fence and to the merge-back escape check (ADR-0068 §D11) — a fact that is load-bearing for both and
was verified, not assumed.

**Step 5.0.2 — A feature branch is checked out, not the default branch.**
```bash
git symbolic-ref --short HEAD
```
Resolve the remote's default branch — do not hardcode `main`:
```bash
git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'
```
If that prints nothing (no remote, or the local symref cache is missing), fall back to:
```bash
git remote show origin 2>/dev/null | sed -n 's/^ *HEAD branch: //p'
```
If both are empty, fall back to the literal `main` — documented here, never a silent hardcode. If the checked-out branch equals the resolved default → refuse to dispatch. Print the literal remediation command: "Recovery-readiness pre-flight: HEAD is on `<default>`, the default branch. Run `git checkout -b feat/<slug>` and re-invoke Step 5." Do not proceed to dispatch-mode selection.

**Step 5.0.3 — HEAD sha recorded as the recovery baseline.**
```bash
git rev-parse HEAD
```
Record as `BASELINE_COMMIT`. Write it once to the manifest via bash sed substitution on the additive field (NOT via Edit tool, NOT via `manifest-set-flag.sh`, which is boolean-only): <!-- path-rule-exempt: negated -- tells the reader NOT to use this helper for this write, never invokes it -->
```bash
sed -i.bak 's/^recovery_baseline_sha: null$/recovery_baseline_sha: "<BASELINE_COMMIT>"/' "<manifest>"
```
If `manifest.recovery_baseline_sha` is already non-null (a resumed Step 5 run), skip the write — it is written once, at pre-flight, and never rewritten by a later step. A baseline that moves is not a baseline (ADR-0050 §D3).

**On that resumed-run branch, check the recorded baseline is still reachable (issue #244,
ADR-0103).** §D3 guarantees the *field* does not move; it never guaranteed the *history under it*
does not. Measured on this repository's two recorded baselines, one is already orphaned — the one
whose chain was paused.

<!-- fence-contract: c2c-step5-baseline-ancestry -->
```bash
# ADR-0133 §D1 (issue #394): the body between the two FENCE_BASH lines runs under BASH, not under
# the host shell. No `export` prologue — this body binds everything it reads, from the substituted
# `<baseline>` placeholder. Terminator at COLUMN 0; an indented one is swallowed into the
# here-document and destroys this fence's exit code silently.
bash <<'FENCE_BASH'
git rev-parse --git-dir >/dev/null 2>&1 || { echo "BASELINE_NOREPO"; exit 3; }
_b="<baseline>"
[ -n "$_b" ] || { echo "BASELINE_NOREPO"; exit 3; }
if ! git cat-file -e "$_b" 2>/dev/null; then
  echo "BASELINE_GONE $_b"
elif git merge-base --is-ancestor "$_b" HEAD 2>/dev/null; then
  echo "BASELINE_OK $_b"
else
  echo "BASELINE_ORPHANED $_b"
fi
exit 0
FENCE_BASH
```

**This is a report, not a halt**, and the distinction is the decision: the run is not damaged, only
its recovery path is, so stopping a healthy chain over a dead baseline would trade a working run for
a hypothetical one. Render whichever line applies and proceed:

- `BASELINE_OK` — say nothing.
- `BASELINE_ORPHANED <sha>` — *"Recovery baseline `<sha>` is no longer an ancestor of this branch
  (the branch was rebased). The object survives in the reflog only, so it is one `git gc` from
  being unrecoverable. A recovery reset to it would detach from this branch's history. Find the
  equivalent commit with `git log --format='%H %s' | grep <subject>` before relying on it."*
- `BASELINE_GONE <sha>` — the same, plus: the object no longer exists at all and there is nothing to
  reset to.
- exit 3 — the check did not run. Say so; do not report a clean baseline.

**The operational rule, which nothing stated before #244: merge `main` into the feature branch; do
not rebase it, once `recovery_baseline_sha` is set.** A merge preserves the recorded commit as an
ancestor and the baseline stays meaningful; a rebase orphans it. This matters because the sequence
that triggers it is the normal one, not an exotic one — Step 5 records the baseline, something halts
the run, fixing the blocker means a PR to `main`, and resuming means bringing the branch up to date.

**The field is never corrected to match reality**, even when this check says it is orphaned. §D3's
write-once rule is worth more than any single record, and a baseline that gets "fixed" whenever it
looks wrong is a baseline again only in name.

**Step 5.0.4 — `worktree.baseRef` is `"head"` in the effective `settings.json` (ADR-0068 §D1, R-05).**
```bash
python3 -c "import json,os,sys; p=os.path.expanduser('~/.claude/settings.json'); d=json.load(open(p)); sys.exit(0 if d.get('worktree',{}).get('baseRef')=='head' else 1)"
```
Non-zero — including a missing or unparseable `settings.json` — counts as **not verified**. **This assertion fails closed**, and that is deliberate: every hook in this repository follows the opposite convention, allow-on-every-failure-mode, so a reader who pattern-matches on that convention will guess this one should fail open too and "fix" it into doing so. It does not, because it is a pre-flight assertion, not a hook, and it sits beside ADR-0050's other three assertions above, which also fail closed. On refusal, print the literal remediation: "Recovery-readiness pre-flight: set "worktree": { "baseRef": "head" } in ~/.claude/settings.json and re-invoke Step 5. Without it every modification agent's worktree forks from the default branch and cannot see this feature branch's commits (ADR-0068 F15)." Do not proceed to dispatch-mode selection. On success, record `bash ~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh <manifest> worktree_baseref_verified true`; on refusal, leave it at the `manifest-init.sh` default of `false`.

**Autopilot (`manifest.autopilot = true`) refuses identically — no leniency branch (ADR-0050 §D6).** A dirty tree, a default-branch checkout, or an unverified `worktree.baseRef` halts the unattended path exactly as it halts the attended one. There is no `AskUserQuestion` on this path, so the remediation command above is recorded in the report rather than prompted to a terminal nobody is watching.

**Step 5.0.4b — a trusted `xcodebuild` test-cmd names its own build root (issue #488, ADR-0159).**
Only when `.claude/test-cmd`'s first non-comment, non-blank line (the same line stop-gate.sh's own
`CMD=$(awk …)` reads) contains the literal substring `xcodebuild`:
```bash
grep -q -- '-derivedDataPath' .claude/test-cmd
```
Absent means every worktree this feature dispatches into shares one build root with the main
checkout and with every other worktree — `detect-test-cmd.sh` writes the flag into every candidate
it generates now, but an EXISTING trusted `.claude/test-cmd` predates that and is untouched by it
(the script leaves a present file alone, by design, ADR-0023 §D3). Two concurrent `xcodebuild` runs
then overwrite each other's products; the observed cost was an unsigned framework and a false red,
the dangerous direction is a stale product reporting green on a broken tree. **Fails closed, the
same posture as 5.0.4 beside it** — this is a pre-flight assertion, not a hook, and a shared build
root is exactly the kind of defect that reads as nothing wrong until two worktrees race. On
refusal, print the literal remediation: "Recovery-readiness pre-flight: .claude/test-cmd runs
xcodebuild without -derivedDataPath, so every worktree this feature dispatches would share one
build root. Add -derivedDataPath \"<project-root>/.build/DerivedData\" to it and run:
bash ~/.claude/hooks/approve-test-cmd.sh \"<project-root>\" — then re-invoke Step 5." Do not
proceed to dispatch-mode selection. Not a manifest flag: unlike 5.0.4, nothing downstream reads a
recorded verdict for this one, so there is nothing to set on success.

**Step 5.0.5 — enter `step_5_implementation` (issue #248, ADR-0095). Runs only after all five
assertions above have passed, and is the LAST thing before dispatch-mode selection.**

```bash
bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh "<manifest>" step_5_implementation
```

This is the chain's only unconditional producer of that state, and without it Step 5 can be entered
but never left: every "transition to `step_6_review`" further down needs `step_5_implementation` as
its source, and the manifest was still at `ready_for_implementation`. Step 4.5's `green` branch also
performs this transition, but Step 4.5 runs only when `tracer_bullet_mode = probe` and
`manifest-init.sh` writes `skip`, so on a default run nothing performed it at all.

**Running after Step 4.5 is a no-op, not an error** — `manifest-transition.sh` returns 0 on a
same-to-same call. That is what lets both producers coexist instead of one having to guard against
the other; do not add a conditional here.

**Placement is load-bearing in the other direction too.** Every refusal above prints "Do not proceed
to dispatch-mode selection" and leaves the manifest at `ready_for_implementation` — the state a Form
B resume is defined for. Transitioning earlier would strand a refused pre-flight in a state its own
recovery path does not accept.

#### Pattern seed handoff (ADR-0057 §D5, only if Step 4.5 ran and computed `green`)

If `manifest.tracer_bullet_verdict = green`, every coder brief dispatched below — Workflow path and
Agent-tool fallback alike — for a task touching the same layer(s) the tracer-bullet slice touched
MUST add one line: `"Follow the pattern already established in <tracer-bullet slice file list>
(Step 4.5 tracer-bullet probe) — do not re-derive the approach from scratch."` This is the single
resolution site for that instruction, stated once here so both dispatch branches below honor it
without a second copy going stale independently — the same convention `#### Proportional audit
depth` above already uses for its own single resolution site (ADR-0049 §D5 precedent). If
`tracer_bullet_verdict` is `null`/absent (Step 4.5 skipped or not yet run), this subsection is a
no-op.

**Dispatch mode selection:**
- If `manifest.hook_verified = true`: use Workflow dispatch path (below).
- If `manifest.hook_verified = false` or `null` (field absent): present smoke test gate (see
  "Smoke test gate" block below) and STOP until user records result.
- If Dynamic Workflows is unavailable or the `ultracode` keyword (renamed from `workflow` in CC v2.1.160) does not trigger script generation:
  fall back to Agent-tool batch dispatch (see "Fallback — Agent-tool batch dispatch" below).
  Set `step5_mode: "agent_batch"` via bash sed substitution (same as the fallback section below).

**Pre-dispatch: worktree isolation check (the git-dir check runs ONCE before any dispatch, before
dispatch-mode selection and before every stage in every task group below):**
```bash
git rev-parse --git-dir 2>/dev/null
```
The worktree is created from the CWD of the session, not from `project_root` — check the CWD,
not `project_root`. If the CWD is not inside a git repo the worktree will fail even if
`project_root` has its own `.git`.
- exit 0 → CWD is inside a git repo → dispatch coder **with** `isolation: worktree`. There is no
  second mode (ADR-0068 §D1, §D10).
- exit non-0 → refuse to dispatch. Print the literal message: "Worktree isolation contract: the
  session CWD is not inside a git repository. The chain cannot dispatch a modification agent
  here. Run the chain from inside the repository, or `git init` the project root, and re-invoke
  Step 5." Do not proceed to dispatch-mode selection.

**No two concurrent builds share a build root (issue #488, ADR-0159).** `isolation: worktree` gives
each dispatch its own working directory; it does not by itself give a compiled-language build its
own build output directory, and a shared one is invisible until two worktrees race on it. 5.0.4b
above is the gate for a project whose test-cmd names one explicitly. The controller-side
verification a checkpoint runs (below, and at the Step 6 review) is not started while a dispatch it
depends on is still in flight — the merge-back block's own ordering already enforces this for
content; this is the same invariant stated for build state.

**Pre-dispatch: artifact existence check (run before any dispatch):**
```bash
test -f "<manifest.artifacts.adr>"  || echo "MISSING_ADR"
test -f "<manifest.artifacts.plan>" || echo "MISSING_PLAN"
```
If either path is missing on disk: do NOT dispatch coder. Present to user:
> "Artifact not found: `<missing path>`. Architect may have truncated before writing the file. Re-run architect dispatch (Step 2) or restore the file manually."

**Pre-dispatch: plan structure validation (run after existence check):**
<!-- fence-contract: concept-to-code-step5-plan-structure -->
```bash
# ADR-0133 §D1 (issue #394): the body between the two FENCE_BASH lines runs under BASH, not under
# the host shell, which is zsh here and differs from bash on word splitting, unmatched globs and
# `echo` escapes. No `export` prologue — this body has no free variables; the plan path arrives as a
# substituted placeholder. Terminator at COLUMN 0; an indented one is swallowed into the
# here-document and destroys this fence's exit code silently.
bash <<'FENCE_BASH'
# plan-tasks.sh owns the definition of a plan task (ADR-0069 §D1/§D3, issue #172). Do NOT inline a
# grep here: the architect is allowed BOTH `### Task 3 — …` headings and `- [ ]` checkbox items
# (architect.md Output Format); a checkbox-only count rejects 9 of the 62 plans in the corpus
# (re-measured 2026-08-03, ADR-0121), and three files each holding their own answer is the defect
# #172 was filed about.
# This is a CHECKER — branch on its exit code. The anti-test-weakening scan four blocks below and
# the diff-budget reporter are the opposite contract (always exit 0, signal on stdout, print
# CLEAN). Do not copy one block's branching into the other.
# The trailing `# plan-tasks-question:` comment on each invocation declares which question it
# answers; mode-binding-check.sh compares that declaration against plan-tasks.sh's own
# mode-contract table, never against this prose (issue #294, ADR-0131).
tasks=$(bash ~/.claude/skills/concept-to-code/scripts/plan-tasks.sh --count "<manifest.artifacts.plan>")   # plan-tasks-question: guard
rc=$?
openers=$(bash ~/.claude/skills/concept-to-code/scripts/plan-tasks.sh --count-openers "<manifest.artifacts.plan>")   # plan-tasks-question: arithmetic
orc=$?
FENCE_BASH
```

**This fence carries no ADR-0133 §D4 print, and that is a stated exception rather than an
oversight.** Under the wrapper `$tasks`, `$rc`, `$openers` and `$orc` do not survive the terminator,
so the four paragraphs below — and the batch-dispatch policy further down, which reads `$openers` —
name values the orchestrator must carry from this block's own run, exactly as it carries
`<manifest.artifacts.plan>` into it. The §D4 remedy is normally a printed token; here it is not
available, because this block's stdout is asserted BYTE-EXACTLY by an existing execution
(`plan-task-count.test.sh`, section PTF, compares the whole of it against `tasks=[N] rc=[N]`), and a
new line would break a green assertion to satisfy a convention. Read the two counts off this block's
own invocation; do not add a print here without moving that assertion first.

**Two counts, two questions, and using one for the other is issue #242 (ADR-0100).** `$tasks` is
the loose predicate and answers *"is there any task at all"* — it is for the `>= 1` guard below and
for nothing else. `$openers` is the strict predicate and answers *"how many task blocks are there"*
— it is for the batch-dispatch policy in the Agent-tool fallback and for nothing else. Measured
over the 58 corpus plans, the two differ on 51, all of them `>= 6` and over-counted; on #222's plan
they are 38 and 7, and batches of 2-3 over 38 dispatch against tasks that do not exist. **Do not
substitute one for the other in either direction.**
If `rc = 2` or `rc = 3`: do NOT dispatch coder — **the check did not run**, which is not the same as
finding no tasks. Report the script's stderr verbatim and stop.

If `tasks = 0`: do NOT dispatch coder. Present to user:
> "Plan at `<manifest.artifacts.plan>` contains no recognisable task. A task is either a `## Task N — …` heading (H2–H4) or a `- [ ]` checklist item. Open the plan, verify the task list, and re-invoke Step 5."

**Pre-dispatch: anti-test-weakening baseline mark (ADR-0047):**
```bash
_pre5=$(git rev-parse HEAD 2>/dev/null)   # anti-test-weakening gate baseline (ADR-0047)
_pre5_ts=$(date -u +%s)                   # elapsed_wall_seconds baseline (ADR-0064, issue #118)
```
An empty `_pre5` (no commits yet, or the CWD is not a git repository) makes the later
`git diff "$_pre5"` empty, which the scan reports as `CLEAN` — never an error. If `_pre5_ts` is
never recorded (e.g. a resumed session that skipped this block), the Task-level metrics block
below omits `elapsed_wall_seconds` for the rest of this run rather than measuring from an
arbitrary later point.

#### Smoke test gate (pre-dispatch, blocks if hook_verified = false)

If `manifest.hook_verified = false` or `null` or the field is absent from the manifest:

Run the deterministic check. Do NOT ask the user to watch the terminal: a hook that never fired and a
hook that fired and stood down look identical on screen. `pre-flight-pattern-enforce.sh` records every
decision it makes to its own audit log, and that log is the evidence.

> **The path below is the DEPLOYED one and is deliberately not the staging shape** (issue #212).
> `hook-verify-workflow.sh` is vendored flat at `staging/plugin/scripts/`, by ADR-0016 and ADR-0024;
> `sync-to-claude.sh`'s PAIRS remaps it into `skills/concept-to-code/scripts/` on deploy. So
> `staging/plugin/skills/concept-to-code/scripts/hook-verify-workflow.sh` does not exist, and a path
> check run against staging reports it as missing — correctly, and harmlessly. Do not "fix" this
> reference to a staging-shaped path: it would read a file sync never writes there.

**Step A — mark, and make a scratch file:**
```bash
MARK=$(bash ~/.claude/skills/concept-to-code/scripts/hook-verify-workflow.sh --mark)
SMOKE_DIR=$(mktemp -d); printf 'hello\n' > "$SMOKE_DIR/test.txt"
```

**Step B — dispatch exactly one workflow agent, spawned as a coder.** Send this prompt:
```
ultracode — use a workflow with exactly one agent, spawned with agentType: 'coder',
to append the line 'smoke test ok' to <SMOKE_DIR>/test.txt.
```
The `agentType: 'coder'` is load-bearing. A default workflow subagent reports
`agent_type=workflow-subagent`, and the guard bypasses on its agent_type check without enforcing.

**Step C — check:**
```bash
bash ~/.claude/skills/concept-to-code/scripts/hook-verify-workflow.sh --check "$MARK"
```

Record by exit code:
- **exit 0 (VERIFIED)** → `bash ~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh <manifest> hook_verified true`
  (the helper supports any top-level unquoted boolean key). Proceed to the Workflow dispatch path.
- **exit 1 (REFUTED)** → `bash ~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh <manifest> hook_verified false`.
  Proceed to Fallback (Agent-tool batch dispatch). The printed reason names which failure occurred:
  no decision recorded after the marker (hooks disabled, or the workflow never dispatched), every
  workflow agent reported `workflow-subagent` (the dispatch omitted `agentType: 'coder'` — a
  workflow-script bug, not a platform limitation), or every decision after the marker belongs to a different, concurrent Claude Code session
  (`CLAUDE_CODE_SESSION_ID` was set and filtered them out — issue #33).
- **exit 3 (INCONCLUSIVE)** → record NOTHING, do not call `manifest-set-flag.sh`. Either the audit log <!-- path-rule-exempt: negated -- instructs skipping this helper on the INCONCLUSIVE branch, not invoking it -->
  is missing (`pre-flight-pattern-enforce.sh` is not installed — fix the install, then re-run), or
  `CLAUDE_CODE_SESSION_ID` was unavailable and the post-marker window mixed rows from more than one
  concurrent Claude Code session, so the check cannot tell which one is this session's (re-run when no
  other session is active, or on a CLI version that sets `CLAUDE_CODE_SESSION_ID` — issue #33). The
  printed `reason=` line names which of the two applies. **Never record `false` on exit 3.** Neither
  cause is evidence that hooks fail to fire.

Do not run the check while another coder agent is working in this session: the audit log does not
distinguish a workflow coder from an Agent-tool coder.

IMPORTANT: if `hook_verified = false`, the workflow path is blocked and the chain uses the Agent-tool
batch dispatch (fallback).

The gate fires ONCE per manifest. After `hook_verified` is recorded, the gate is silent for
all subsequent Step 5 runs on the same manifest.

**[Autopilot default (`manifest.autopilot = true`): do NOT display the smoke-test procedure and do NOT
wait for a human. If `hook_verified` is `true`, take the Workflow path; otherwise record
`hook_verified = false` via `~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh` and take the Agent-tool fallback. Emit:
"Step 5: autopilot — workflow smoke test skipped, using <workflow|fallback> ✓". This prevents an
unattended run from stalling on the smoke-test prompt, and never takes the Workflow path unless hooks
were already verified true.]**

#### Workflow dispatch path — Step 5 implementation (hook_verified = true)

**CONSTRAINT — NO inline source code in the generated workflow script:**
Agent prompt strings in the JS workflow script MUST reference files by path only — never inline raw source code blocks. Embedding language-specific generics (e.g. `Array<T>`, `Result<T, E>`) or type annotations directly in JS template literals triggers a parse error (`Unexpected token`). If context requires a code snippet, write it to a temp file and pass the path to the agent.

**Before dispatch — parallel task conflict scan (GAP E, R-10, ADR-0068 §D8):**
Read the plan at `<manifest.artifacts.plan>`. Scan each task description for explicit file-path mentions (lines containing `/` paths or filenames with extensions). The scan is binding now, in every case — merges are real (§D5), so a genuine conflict halts the run (see the Conflict halt below), not merely warns past it. If the same file path appears in multiple task descriptions, those task groups are sequenced instead: dispatched one after another, never in the same `parallel()` batch, so each group's worktree merges into the feature branch before the next group's coder forks from it. Emit before dispatching:
> "File conflict risk: `<path>` appears in tasks <N> and <M>. Sequencing these task groups instead of dispatching them in the same parallel() batch."
Groups with no path overlap keep the default parallel dispatch — sequencing is scoped to the conflicting groups only.

Step 5 dispatch prompt (send as a single message to the session):
```
ultracode — use a workflow to dispatch the following coder tasks in parallel.
IMPORTANT: The workflow script must be deterministic — do NOT use Date.now(), new Date(), or Math.random(). These calls throw at runtime and break workflow resume (CC 2.1.172 removed the validation warning but the runtime constraint remains).
Read plan at <manifest.artifacts.plan>.
Read ADR at <manifest.artifacts.adr>.
Read SPEC.md at <manifest.artifacts.spec>.
Read project CLAUDE.md at <manifest.artifacts.project_claude_md> (if not null).

[IF $_project_context is non-empty — add this block, otherwise omit entirely:]
## Project Roadmap (multi-feature context)
<insert full content of PROJECT.md here>
**Declare any plan constraint you do not implement (ADR-0073 §D1, issue #178).** If the plan
specifies something concrete — a validation bound, an interface shape, a named approach — and you
decide against it, do NOT implement it silently. Emit one line per case in your report, in the
terminal `PLAN DEVIATIONS:` block, before `PATTERN:`:

```
PLAN DEVIATIONS:
- task <N> | <the constraint, quoted or closely paraphrased> | declined|altered | <one line: why>
```

Emit the literal line `PLAN DEVIATIONS: none` when there are none. Deviating is legitimate and
often correct — a plan is written before the code is read. What is not legitimate is deviating
without saying so, because the human approving Gate 5 then has to find it by reading the diff.

Implement ONLY what is specified in the plan above. Do NOT implement features marked [ ] (planned but not yet started) or re-implement anything marked [x] (already done). Use the roadmap only to understand existing interfaces, naming, and patterns you must stay consistent with.
[END IF]

Build the script with pipeline(), one entry per task group, stages **tester → coder** (extended
with an optional third reviewer stage below when checkpoint review is on) — the tester runs
BEFORE the coder so it is briefed from the specification, never from the implementation
(ADR-0049 §D1: ordering makes the separation a property of the dispatch graph, not a request an
agent holding `Read` can silently ignore). Use your Pre-flight Pattern Classifier (ADR-0001) for
every Edit operation. Auto mode active. No intermediate HITL. `.claude/test-cmd` is off-limits —
never read, write, or modify it. If the test command needs changing, stop and report it to the
orchestrator.

**Stage 1 — tester.** Pin `agentType: "tester"`, `model: "sonnet"`, `effort: "xhigh"`, and
`isolation: "worktree"` explicitly on this `agent()` call — the effort table above is
documentation, not a binding, and an omitted `effort` silently inherits this session's `high`
(ADR-0018 addendum; ADR-0049 §D6 applies the same rule to this new dispatch site). `tester` has
no `isolation` in its own frontmatter (F5), and frontmatter never reaches the Workflow path
anyway (F4 as corrected by ADR-0068 F16), so an omitted value here means no worktree at all, not
an inherited default (ADR-0068 §D6, R-09). Brief the tester from the SPEC's requirement
IDs, never from implementation files (none of this group's implementation exists yet):
```bash
bash <spec-coverage.sh, resolved exactly as in the Requirement-ID coverage gate below> \
  --spec <manifest.artifacts.spec> --plan <manifest.artifacts.plan> --list
```
- Output lists one or more `R-NN` identifiers → brief the tester with that list: one failing test
  per requirement ID this task group covers.
- Else (the SPEC declares no IDs) → brief the tester from the SPEC's Success Criteria section,
  verbatim.
- Else (Success Criteria is also absent or empty) → brief the tester from this task group's plan
  task text.
The tester writes failing tests only, for this task group, and reports back which requirement
IDs (or which Success Criteria / plan-task lines, per whichever fallback fired) each test covers.

**On a compiled or type-checked language, add this to the brief verbatim (issue #486, ADR-0155
§D1):** leave the target BUILDING. Declare the interfaces, protocols or types your tests reference
but which do not exist yet — the signature is yours, and the coder owns the body. A test that names
a type nobody has written does not fail, it stops the target from compiling, and then no assertion
runs at all and the red you were dispatched to produce does not exist. Declaring an interface is not
implementing it: you are writing the boundary the specification already fixes, not the code that
satisfies it, so this takes nothing away from writing the tests before the implementation.
`test-write-scope.sh` constrains the coder only, so nothing blocks you from writing that declaration
on a production path.

**The fallback chain above decides WHAT to assert. The plan decides WHERE and under what name, and
is read in every case — never as a fallback (ADR-0088, issue #241).** Add to the brief: work
through this task group's sub-steps and execute every one that creates or edits a test file. Those
sub-steps belong to the tester, because the coder dispatched next is denied them by
`test-write-scope.sh` — so a skipped sub-step is a sub-step nobody can do. Where a sub-step says to
confirm a failing assertion and stop, it stops: a red assertion left red is the deliverable, not an
unfinished task. The tester reports which sub-steps it executed and which it leaves to the coder.

Also add to the brief: Writes go under the dispatched worktree, never to an absolute path into the shared checkout: `isolation: worktree` bounds the working directory, not the filesystem, and an absolute path resolves out of it (ADR-0068 §D11, issue #245). Read the planning artifacts by absolute path; write by relative path.

#### Merge-back and base-fork audit (ADR-0068 §D5, §D6, §D9)

One resolution site, referenced by Step 5's Workflow stages above and below and by the Agent-tool
fallback below — stated once, the same convention as `#### Pattern seed handoff` and
`#### Proportional audit depth`. It runs after the tester's `agent()` call above returns and before
Stage 2 below creates the coder's worktree.

**Not referenced by Step 6's fix-agent dispatch (issue #412, corrected 2026-08-22).** This
paragraph used to list it as a third call site. It never was one: Step 6's Workflow path runs
Phase 3's fixes and Phase 4's re-review inside one continuous workflow invocation with no
orchestrator turn between them, so this per-stage merge-back — designed to run BETWEEN two
`agent()` calls the orchestrator dispatches separately — has nowhere to run inside it. Step 6 uses
the skill fallback unconditionally instead (see Step 6, above).

**The orchestrator commits, never the agent.** `coder.md`'s "never commits" instruction is
untouched by this feature; this snapshot happens only after the dispatch has already returned
(R-08). `$PRE` = `git rev-parse HEAD` on the feature branch, captured immediately before this
stage was dispatched.

`$WT` and `$WB` are obtained differently depending on dispatch path — there is no single method
that covers both:

- **Agent-tool path:** `$WT` = `worktreePath`, `$WB` = `worktreeBranch`, both read directly from
  the dispatch result alongside the agent's report (F10).
- **Workflow path:** the dispatch result carries no worktree identity at all (F19) — the run
  journal records only `agentId`, `key`, `result` and `type`, and the task notification carries no
  worktree block, though the worktree itself IS created (F16). Locate it by enumerating
  `git worktree list` and selecting the entry that is not the main working tree. Prefer
  enumeration over deriving the path from the run id: F20 records `.claude/worktrees/<runId>-<n>`
  (worktree branch `worktree-<runId>-<n>`) only as an observed naming convention, not a reported
  contract, and relying on it is exactly the class of undocumented assumption this ADR exists to
  stop. The convention may be noted as a documented fallback, but only subordinate to enumeration,
  never as the primary mechanism.

Do not collapse these back into one method: the Workflow path does not report worktree identity
(F19), so assuming F10's fields apply there leaves the coder's work orphaned on an unmerged
branch — precisely the defect this feature exists to repair, reappearing on the other dispatch
path.

<!-- fence-illustration: carries `<base-fork halt: …>` and `<conflict halt: …>` pseudo-code in place of the halt procedures, so it does not parse as bash and cannot be executed; it specifies a protocol for the orchestrator to follow, not a script to run -->
```bash
# $PRE = git rev-parse HEAD, captured on the feature branch BEFORE this stage was dispatched
# $WT / $WB — Agent-tool path: worktreePath / worktreeBranch, from the dispatch result (F10).
#             Workflow path: no identity is reported (F19) — enumerate `git worktree list` and
#             select the entry that is not the main working tree instead of deriving the path
#             from the run id (F20 is an observed convention, not a contract).
# ESCAPE CHECK (ADR-0068 §D11, issue #245) — runs BEFORE the merge, on the SHARED checkout, not
# the worktree. `isolation: worktree` bounds the agent's cwd, not its filesystem reach: an
# absolute path resolves and writes here. Untracked, not `--porcelain`: the manifest is
# legitimately modified-tracked throughout Step 5 (issue #239), so a dirty-tree check would fire
# on every stage. The chain itself creates no untracked file in Step 5 — step5-report.json is
# gitignored — so anything here came from outside the worktree it was supposed to stay in.
ESCAPED=$(git ls-files --others --exclude-standard 2>/dev/null)
[ -z "$ESCAPED" ] || <escape halt: report $ESCAPED as written outside the dispatched worktree,
                      preserve $WB, do NOT merge, stop>
[ -d "$WT" ] || { echo "nothing to merge: worktree auto-removed"; }   # F6, not an error
if [ -d "$WT" ] && [ -n "$(git -C "$WT" status --porcelain 2>/dev/null)" ]; then
  BASE_SHA=$(git -C "$WT" rev-parse HEAD)      # fork point, captured BEFORE any commit lands
  [ "$BASE_SHA" = "$PRE" ] || <base-fork halt: report both shas, preserve $WB, stop>
  git -C "$WT" add -A
  git -C "$WT" commit -m "chore(step5): snapshot <stage> worktree (<agent_type>)"
  git merge --no-edit "$WB" || {
    CONFLICTS=$(git diff --name-only --diff-filter=U)   # capture BEFORE the abort below — it clears the unmerged paths; do not reorder these two lines
    git merge --abort
    <conflict halt: report worktree branch $WB and $CONFLICTS, preserve the branch, stop>
  }
  git worktree remove "$WT" 2>/dev/null || true
fi
```

Either check in the `if` failing is **"nothing to merge"** — not an error, no forced empty
commit, and no `worktree_merges` entry (R-14). On a successful merge,
append one `worktree_merges` entry — `{stage, agent_type, branch, base_sha, merge_result}` — to
`step5-report.json`; append none when nothing was merged. The array is additive: its absence in
an older report means the run predates this feature, not that the report is malformed. After a
successful merge the worktree is pruned; an **unmerged** worktree (halted, or left over from a
conflict) is reported and preserved, never silently deleted.

**Escape halt, and why it runs before the merge rather than at commit time (ADR-0068 §D11, issue
#245).** An agent that writes through an absolute path lands in the shared checkout, and the damage
is not the file — it is the merge. `git merge` refuses to overwrite an untracked file at a path the
merge wants to create, so a stray write at exactly the path the worktree branch adds aborts the
merge and gets reported as a conflict whose named cause is wrong. Checking here names the real one.
`commit`'s Step 1 untracked list (ADR-0062) would catch the same debris several steps later, which
is too late to protect this.

Measured, not assumed (issue #245): the agent's `pwd`, `git rev-parse --show-toplevel` and the
`PreToolUse` payload's `cwd` are all the worktree, and `tool_input.file_path` arrives resolved to an
absolute path. **A `PreToolUse` hook keyed on that would still not have caught the observed
incident**, which came through `mkdir`/`cp` — Bash, whose `tool_input` carries no `file_path` at
all. That is why this check is here and not in a hook.

**Base-fork halt, and why it is a halt, not a report.** `BASE_SHA != $PRE` means the worktree
forked from somewhere other than the feature branch — the exact defect this feature exists to
fix, occurring after the Step 5 pre-flight assertion (R-05) already passed: a mid-run edit to
`settings.json`, or a future CC build changing the semantics. It halts on the same path as the
Task 7 conflict halt, naming both shas, rather than merely reporting the mismatch. The
false-positive analysis is short enough to state here: the stage protocol serialises dispatch →
merge → next dispatch, so `HEAD` cannot legitimately move between `$PRE` and the sha the worktree
reports, and the auto-removed and empty-diff cases are already handled as nothing-to-merge above
this comparison. A mismatch is therefore always the defect, never a false alarm.

**Conflict halt, and why no automatic resolution is attempted (R-12, ADR-0068 §D8).**
`git merge --no-edit "$WB"` failing means the just-committed worktree snapshot and the feature
branch touched the same lines. `$CONFLICTS` is captured with `git diff --name-only
--diff-filter=U` BEFORE `git merge --abort` runs — the abort clears the unmerged-paths state
`--diff-filter=U` reports, so capturing it afterward would yield nothing; this is exactly the kind
of ordering a later edit could "tidy" into breakage, which is why the code comment says so
directly. The halt reports the worktree branch name (`$WB`) and `$CONFLICTS`, preserves the branch
(no `git worktree remove`, no branch deletion), and stops. No automatic resolution is attempted:
no rebase, no `-X ours`, no resolver dispatch — an automatic rebase over agent-authored work can
produce a syntactically valid, semantically wrong result that no gate in this repository would
catch. Under autopilot the halt is recorded in `step5-report.json` rather than prompted to a
human, the same non-interactive behavior ADR-0050's assertions already apply elsewhere on this
path. This shares the same `if` block as the base-fork halt above; the two halts are distinguished
by their message, not duplicated as two separate checks.

**Ordering.** This merge-back completes — the tester's worktree is committed and merged into the
feature branch — before Stage 2 below creates the coder's worktree, so the coder forks from a
`HEAD` that already contains this task group's red tests (R-09). `worktree.baseRef: "head"` does
not make this step redundant: `"head"` means the commit `HEAD` points at, not the working tree,
and a worktree forks from a commit — the tester's output is uncommitted until this merge lands it
there (ADR-0068 §D6, §D9).

**Stage 2 — coder.** Pin `agentType: "coder"`, an explicit `model` (per the model-override rule
above), an explicit `effort` (per the effort table above), and `isolation: "worktree"` explicitly
(ADR-0068 §D1, §D7) — there is no second mode. Every
coder prompt at this stage MUST include, verbatim, ASCII hyphen (ADR-0049 §D3 — a paraphrase or
an em dash leaves the guard silently inert, issue #87):
```
TEST-AUTHORING SCOPE - the tester agent owns test files for this task. Do NOT create or edit tests.
Sub-steps in your tasks that create or edit test files were executed by the tester before this
dispatch and are NOT yours. Do not repeat them and do not edit those files. If that leaves a task
looking incomplete, say so in your report rather than closing the gap yourself. Make the red tests
green, except where the plan defers a red assertion to a later task: an assertion the plan defers
to a later task stays red, and your report says which one and why.
Writes go under the dispatched worktree, never to an absolute path into the shared checkout: `isolation: worktree` bounds the working directory, not the filesystem, and an absolute path resolves out of it (ADR-0068 §D11, issue #245). Read the planning artifacts by absolute path; write by relative path.
```
A coder whose write is denied by `test-write-scope.sh` is reading a consistent story: the tester
agent owns test files for this task, and the correct response is to report the gap to the
orchestrator, not to retry the write.

**Pin the model explicitly on every agent() call (no CLI-model inheritance):** in the
Workflow path a subagent dispatched with `agentType` but **no** `model` inherits the main-loop
(CLI session) model, NOT the agent's frontmatter. To keep the chain on its configured models
regardless of which model the orchestrator session runs, ALWAYS pass an explicit `model`:
- `manifest.coder_model = "opus"` (or legacy `"fable"`) → `agent(prompt, { agentType: "coder", model: "opus", ... })`.
- `manifest.coder_model = "sonnet"` or null → `agent(prompt, { agentType: "coder", model: "sonnet", ... })` (still explicit — do NOT omit `model`, or the coder would inherit the CLI model).

**Pin `effort` explicitly too, for the same reason.** The Workflow tool documents `opts.effort` as
"omit to inherit the session effort", so an omitted `effort` behaves exactly like an omitted
`model`: the subagent takes the orchestrator session's value instead of the one pinned in its own
frontmatter. Raising the orchestrator's `effortLevel` would then silently raise every dispatched
agent with it, which is both a cost increase nobody asked for and a loss of the per-agent
calibration. Pass the agent's own frontmatter value on every `agent()` call:

| agentType | effort |
| --- | --- |
| `architect`, `coder`, `tester` | `xhigh` |
| `reviewer`, `debugger` | `high` |
| `refactorer` | `medium` |
| `doc-writer`, `researcher` | `low` |

If an agent's frontmatter changes, this table is the second place to update — they are not
linked, and a mismatch here silently overrides the file.

[IF manifest.step5_review_mode = checkpoint — add this block to dispatch, otherwise omit entirely:]
Checkpoint review: ON (ADR-0039 D5-D9).
Extend the tester → coder pipeline() above with a third stage: reviewer.
Do NOT use parallel() as a barrier between the stages — task B must keep implementing while
task A is under review. Wall-clock is the slowest single-task chain, not sum-of-slowest-per-stage.
Stage 3 dispatches agentType "reviewer" scoped to the files Stage 2 (coder) reported for that task.
Pass an explicit model AND an explicit effort of "high" (same rules as the coder above).
It REVIEWS ONLY and fixes nothing.
Pass each task's BLOCKER and MAJOR findings into the prompt of the next task's Stage 2 (coder) as
"found in task <N>, do not repeat this". MINOR and NIT are recorded and left for Step 6.
Collect every review into the checkpoint_reviews array of step5-report.json.
[END IF]

After all tasks complete, the final subagent MUST write
<project_root>/.claude/step5-report.json with the schema defined in the
step5-report.json contract section (schema: see ~/.claude/skills/concept-to-code/SKILL.md §4 Step 5 contract).

[IF manifest.anonymize=true — add this block to dispatch, otherwise omit:]
Anonymize mode: ON (ADR-0011).
- Commit messages in Conventional Commits: minimal subject + body. No tool trailers
  (e.g., "Co-Authored-By: Claude", "Generated with Claude Code") — already off via
  settings.json, reiterated here.
- No trace comments in code: no "// added by Claude", AI/task references, generated TODOs.
  Only comments a human author would write.
- No file slop: only files required by the plan (no redundant READMEs, scratch files, notes).
- No decorative emoji unless requested. Concise and technical docs.
```

After the workflow completes:
1. Read `<project_root>/.claude/step5-report.json`.
2. If the file is absent → fall back to `git diff + test run` directly (do NOT re-dispatch).
3. If `tasks_failed` is non-empty OR `test_result` is `red` → failure signal. Present to
   user; do NOT transition to `step_6_review` without user acknowledgment.
4. Run the `Anti-test-weakening gate — Step 5 → Step 6 (ADR-0047)` block once, before
   deciding the transition.
5. Run the `Requirement-ID coverage gate — Step 5 → Step 6 (ADR-0048)` block once, before
   deciding the transition.
6. Run the `Diff budget and scope check — Step 5 checkpoints (ADR-0052)` block once, over the
   cumulative diff and every completed task — it never affects the transition (advisory only).
7. Run the `Task-level metrics — Step 5 checkpoints (ADR-0064, issue #118)` block once, over the
   same cumulative diff and every completed task — it never affects the transition and is not
   surfaced at Gate 5 (metrics, not findings, ADR-0064 §D2).
8. If all tasks passed, `test_result` is `green` or `n/a`, the weakening gate found no
   `WEAKENED` line, and the coverage gate exit code is `0` → transition to `step_6_review`.
   Present Gate 5.

Set `step5_mode: "workflow"` in the manifest (via bash sed substitution on the additive
field — NOT via Edit tool).

#### Generator/verifier separation — tester stage and coder test-write deny (ADR-0049)

Both dispatch paths in this Step (the Workflow pipeline() above and the Agent-tool batch
fallback below) stage a `tester` agent BEFORE the `coder` agent, per task group (ADR-0049 §D1).
The tester writes the failing tests from the SPEC's requirement IDs (`spec-coverage.sh --list`,
falling back to the Success Criteria section and then to plan task text — never from
implementation files, since none exists yet at this point of the pipeline). Ordering, not an
instruction to the coder, is what makes the separation real: a tester briefed after the coder
could Read the implementation at no cost and with no trace, and only ordering removes that.

Enforcement is `test-write-scope.sh`, a `PreToolUse` hook on `Edit|Write|MultiEdit` (registered
by Task 8 of ADR-0049's plan — inert until an operator wires it into `settings.json`). It denies
the **coder** agent any create or edit of a test-file-shaped path, but only when the coder's own
dispatch prompt carries this marker verbatim, ASCII hyphen (never an em dash — issue #87 made a
typographic substitution silently inert once already):
```
TEST-AUTHORING SCOPE - the tester agent owns test files for this task. Do NOT create or edit tests.
```
Both dispatch templates below emit it on every coder prompt. A coder whose write is denied is
reading the same recovery path stated in Stage 2 above: the tester agent owns test files for this
task — report the gap to the orchestrator instead of retrying the write.

This is a guardrail against a shortcut, not a sandbox (ADR-0041/ADR-0045's distinction, applied
again here): a coder that writes a test via `Bash` heredoc, or writes test-shaped content to a
non-test-shaped path, is invisible to this hook. Keying the deny on `agent_type == "coder"` alone
was rejected (ADR-0049 §D3) — RTF Phase 3, `deep-refactor` and this same skill's Step 6 all
dispatch fix agents with `agentType: "coder"` to legitimately repair a broken test, and the
marker, not the agent type, is what distinguishes a Step 5 implementation coder from those.

#### step5-report.json schema and orchestrator read contract

The final workflow subagent writes this file to `<project_root>/.claude/step5-report.json`.
The orchestrator reads it after the workflow exits.

Schema (JSON):
```json
{
  "step5_mode": "workflow",
  "tasks_completed": [1, 2, 3],
  "tasks_failed": [],
  "files_modified": [
    { "path": "<absolute path>", "operation": "edit|create|delete" }
  ],
  "test_result": "green | red | n/a",
  "test_output_tail": "<last 20 lines of test output or empty string>",
  "harness_deltas": "PASS=N FAIL=0 (delta from baseline, or n/a)",
  "checkpoint_reviews": [
    { "task": 1,
      "severity_counts": { "BLOCKER": 0, "MAJOR": 1, "MINOR": 2, "NIT": 0 },
      "blocking_findings": ["<one line per BLOCKER/MAJOR, passed to the next task>"] }
  ],
  "weakening_findings": [
    { "file": "tests/test_billing.py", "reason": "deleted-test-file" }
  ],
  "suspect_findings": [
    { "file": "tests/test_billing.py", "detector": "zero-assertion-test", "line": 42 }
  ],
  "weakening_scan": "ran | unavailable",
  "requirement_coverage": {
    "ids_declared": 6,
    "uncovered": [ { "id": "R-02", "missing": "plan" } ],
    "unscoped": [ { "id": "R-05", "scope_size": 3 } ],
    "status": "pass | fail | no-ids | unavailable"
  },
  "tests_written_by": [
    { "task": 1, "agent": "tester" }
  ],
  "budget_findings": [
    { "task": "3", "files_expected": 1, "files_actual": 2,
      "lines_expected": 120, "lines_actual": 210, "out_of_scope": ["src/unrelated.py"] }
  ],
  "plan_deviations": [
    { "task": "2", "constraint": "<the plan constraint, quoted or closely paraphrased>",
      "action": "declined | altered", "reason": "<one line: why>" }
  ],
  "task_metrics": [
    { "task": "3", "test_count_delta": 2, "deleted_lines": 14,
      "iteration_count": 2, "elapsed_wall_seconds": 187 }
  ],
  "accessibility_i18n_findings": [
    { "item": "labels", "status": "pass | fail | not-applicable", "note": "<one line>" },
    { "item": "contrast", "status": "pass | fail | not-applicable", "note": "<one line>" },
    { "item": "dynamic-type-or-scaling", "status": "pass | fail | not-applicable", "note": "<one line>" },
    { "item": "keyboard-or-assistive-tech-reachability", "status": "pass | fail | not-applicable", "note": "<one line>" },
    { "item": "i18n-unicode-multibyte", "status": "pass | fail | not-applicable", "note": "<one line>" },
    { "item": "i18n-no-english-centric-examples", "status": "pass | fail | not-applicable", "note": "<one line>" },
    { "item": "i18n-no-locale-formatting-assumed", "status": "pass | fail | not-applicable", "note": "<one line>" }
  ],
  "errors": []
}
```

**`task_metrics` is a METRICS array, not a findings array (ADR-0064 §D2) — it is documented here,
in its own paragraph, deliberately outside the "six advisory arrays" roll-up described in the Gate
5 block below.** A finding asserts something is wrong and asks for a decision; a metric is a
number with no claim attached. `task_metrics` carries the four ADR-0064 D1 instrumentation
metrics — test-count delta, deleted lines, iteration count, elapsed wall time — computed once per
Step 5 checkpoint (the same cadence as `budget_findings` immediately above: once after the
Workflow path completes, once per batch checkpoint in the Agent-tool fallback), tagged with the
same `task` checkpoint label. It is **not surfaced at Gate 5, not counted in the advisory roll-up,
and not presented as actionable** — see the "Task-level metrics" block after the Diff budget and
scope check below for how each field is computed, and the Gate 5 block for the explicit exclusion.
Every field within an entry is independently **conditional-if-present**: a field absent from an
entry means that one metric was not measured for that checkpoint, and MUST NOT be read as `0`
(ADR-0064 §D3 — the same rule ADR-0046's exit codes and ADR-0043's completeness check already
apply elsewhere in this codebase, here applied to stored data). A `0` in a present field is a real,
computed zero (e.g. a checkpoint that genuinely deleted no lines). The `task_metrics` array itself
is absent, as a whole, on any manifest predating this feature — that is not malformed either.

**`accessibility_i18n_findings` IS a findings array, unlike `task_metrics` immediately above —
same distinguishing test ADR-0064 §D2 draws for `task_metrics`, opposite answer: a metric is a
number with no claim attached, and `"labels": "fail"` is a claim about the work (ADR-0066 §D2).**
It is written by **Gate 5.05**, not Step 5, so it is a *seventh* advisory-schema finding array in
this same schema — see the Gate 5 roll-up block below for why it is not folded into that block's
six-array count, and the Gate 5.05 block for where it renders instead. Each entry carries one of
the seven named checklist items (four accessibility, three i18n — ADR-0066 §D1/§D3) with a
`pass | fail | not-applicable` status and a one-line note. **It is never a failure signal**
(ADR-0066 §D2 — the gate records an answer, it does not block, a deliberate and disclosed
divergence from the SPEC's "gate, not aspiration" wording). The array is absent, as a whole, on
any chain that touched no UI-shaped file this cycle — the same condition Gate 5.05 already applies
to `ui-layout-audit` (ADR-0066 §D4), not a second one, and absence here is **not malformed**, it
is what a CLI-only or docs-only chain produces.

`checkpoint_reviews` is an empty array when `step5_review_mode` is `none` (the default), which
is also what every manifest written before ADR-0039 means by omitting the field.

**Orchestrator read contract:**
- Stale detection: check file modification time via `stat -f %m <file>` against
  `manifest.last_updated_at` epoch. If the file is older, it is stale (from a prior run).
  Ignore it and use `git diff + test run` directly.
- `tasks_failed` non-empty → failure signal.
- `test_result: "red"` → failure signal.
- Failure signal behavior: present to user, do NOT auto-transition to `step_6_review`.
- `step5-report.json` absent → git diff + test run directly (not a blocking error).
- Schema validation: check that `step5_mode` and `tasks_completed` are present.
  If either is missing, treat the file as malformed → git diff fallback.
- `checkpoint_reviews` is **never** a failure signal. Its findings were already fed forward to
  the next task during Step 5; they do not block the transition to `step_6_review`, where the
  full RTF cycle sees them anyway. A missing `checkpoint_reviews` key is not malformed — it is
  what a `step5_review_mode: none` run produces.
- `weakening_findings` non-empty → **failure signal**, same handling as `tasks_failed`; absent means none and is **not** malformed.
- `suspect_findings` is **never a failure signal** and never blocks the transition to
  `step_6_review`, in attended mode or under autopilot (ADR-0051 §D2). Each entry is a heuristic
  over a diff with no type information and no test execution — the same distinction
  `weakening-scan.sh` itself draws between its `WEAKENED` and `SUSPECT` sentinels (never
  `grep -q '^WEAKENED'` on a `SUSPECT` line, and never the reverse). Absent means none and is
  **not** malformed. It is advisory only: presented at Gate 5 with its per-detector breakdown so
  a human sees it, never acted on automatically (ADR-0051 §D3).
- `requirement_coverage.uncovered` or `requirement_coverage.unscoped` non-empty → **failure
  signal**, same handling as `tasks_failed` — both ride the same `_rc = 1` exit as
  `spec-coverage.sh`'s stdout contract (ADR-0138 §D3): a plan/test citation gap and an
  out-of-scope test mention are two distinct remedies on one blocking channel, never two channels.
  `unscoped` is additive (ADR-0076): its absence means the gate did not write one, never "none
  found" — the same rule `uncovered` already follows. `requirement_coverage` absent as a whole
  means the gate did not write one and is **not malformed** — the malformed check stays
  `step5_mode` + `tasks_completed`, unchanged.
- `tests_written_by` is **never** a failure signal (ADR-0049 §D5). It is self-reported by the
  agents whose separation it describes — the same class of claim ADR-0047 §A3 and ADR-0048 §A7
  already refuse to trust for their own arrays, and this array carries no better authority.
  Absent is **not** malformed — it is what a run before this feature, or a run where
  `test_cmd_placeholder`/`test_cmd_provisional` skipped the tester stage, produces. A `"coder"`
  entry (an implementation coder wrote a test — either `test-write-scope.sh` denied nothing, or
  it was never wired) is surfaced at Gate 5 for a human to read; it is a record, never a gate.
- `plan_deviations` is a **DISCLOSURE, not a gate** (ADR-0073 §D1, issue #178), and never a failure
  signal in any mode. It records a plan constraint the coder chose not to implement, so the choice
  reaches Gate 5 as a list to approve rather than as something the orchestrator must notice while
  reading a diff. Absent means none was declared and is **not** malformed.
  **It is a self-report, and that is fine here precisely because it is not a gate.** This system's
  own rule — do not trust an agent's self-report as the gate (ADR-0047 §A3, RTF Step 3) — is about
  gates. A disclosure feeding a human decision is the opposite case: a coder that hides a deviation
  leaves the reviewer exactly where it was before this field existed, so the field can only add
  information, never remove a check. Nothing verifies it, and nothing should be built on it as if
  something did.
- `budget_findings` is advisory only and **never a failure signal** (ADR-0052 §D3). A per-task line-count ceiling is
  an estimate made before the work by an agent that has not read every file it will touch — it
  will be wrong regularly and in both directions, so a gate on it would halt on noise more often
  than on signal (the same reasoning `suspect_findings` already established for a heuristic
  finding at this same boundary). Absent means either the checker did not resolve or the plan
  declares no budgets on the relevant tasks (ADR-0052 §D1) — either way, **not malformed**.
- `task_metrics` is **never** a failure signal and is **not one of the advisory arrays** —
  it is a METRICS array (ADR-0064 §D2): no claim is attached to a number, so there is nothing
  here to gate on. Absent (the whole array, or any single field within an entry) means that
  metric was not measured for that checkpoint. Never read an absent field as `0` (ADR-0064 §D3):
  a present field's `0` is a real, computed zero; an absent field is not recorded at all, and a
  reader collapsing the two would quietly manufacture a well-behaved-looking task out of one that
  was never measured. Every value computed here comes
  from `git` or from the orchestrator's own dispatch bookkeeping, never from an agent's report
  (ADR-0064 §D4) — see the "Task-level metrics" block below for the exact computation of each of
  the four fields.
- `accessibility_i18n_findings` is **never** a failure signal (ADR-0066 §D2): the gate records an
  answer, it does not block, a deliberate divergence from the SPEC's "gate, not aspiration"
  wording — disclosed here rather than resolved in either direction. It IS one of the
  advisory-schema finding arrays (unlike `task_metrics` immediately above — each entry is a claim,
  `"contrast": "fail"`, not a bare number), it is just written by Gate 5.05 rather than Step 5, so
  it is not part of the six-array Gate 5 roll-up computed before Gate 5.05 has run — see that
  block for the reason. Absent means either no UI-shaped file was touched this cycle (ADR-0066
  §D4, the inherited Gate 5.05 condition) or the array predates this feature — either way, **not
  malformed**.
- Contrast, six arrays in one schema with different gate semantics: `checkpoint_reviews`,
  `tests_written_by`, `suspect_findings`, `budget_findings` and `accessibility_i18n_findings` are
  never a failure signal; `weakening_findings` always is (ADR-0047 §D5, ADR-0049 §D5, ADR-0051
  §D2, ADR-0052 §D3, ADR-0066 §D2). `task_metrics` sits outside this contrast entirely — it is not
  a finding of any kind.

#### Anti-test-weakening gate — Step 5 → Step 6 (ADR-0047)

The orchestrator runs this scan itself — do not trust the agent's self-report for this gate.
This is the same rule `review-triage-fix` Step 3 already applies to CIRCUIT BREAKER B: the
agent whose work is being examined for test weakening is not the one who gets to report on it.

**Resolution:**
```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] \
   && [ -f "$CLAUDE_PLUGIN_ROOT/skills/review-triage-fix/scripts/weakening-scan.sh" ]; then
  _wscan="$CLAUDE_PLUGIN_ROOT/skills/review-triage-fix/scripts/weakening-scan.sh"
elif [ -f "$HOME/.claude/skills/review-triage-fix/scripts/weakening-scan.sh" ]; then
  _wscan="$HOME/.claude/skills/review-triage-fix/scripts/weakening-scan.sh"
else
  _wscan=""     # scan did not run — report it, do not infer a clean result
fi
```

**Scan and blocking idiom.** The script always exits 0 and prints the sentinel `CLEAN` when it
finds nothing over the cumulative diff since the pre-dispatch mark, so the caller branches on
stdout content, never on exit code and never on emptiness:
```bash
if [ -n "$_wscan" ]; then
  _wk=$(git diff "$_pre5" 2>/dev/null | bash "$_wscan" 2>/dev/null)
  if printf '%s\n' "$_wk" | grep -q '^WEAKENED'; then
    # blocking path — see policy below
  fi
fi
```
- `grep -q '^WEAKENED'`, anchored. Never `[ -n "$_wk" ]` — the script prints `CLEAN` when it
  finds nothing, so the output is never empty and an emptiness test is always true:
  **never gate on empty output**.
- **`CLEAN` means "no detector fired", never "no weakening occurred" (ADR-0073 §D4, issue #177).**
  The blind spot with a name: an assertion edited IN PLACE removes one assert-bearing line and adds
  one, so `assert-removed`'s count comparison cannot fire. Flipping `is True` to `is False` to match
  what the implementation produces is invisible to every detector in that script. No detector was
  added — the diff shape is ambiguous by construction and the measurement showed 0-of-2 precision on
  this repository's own history (see the script's header). **When this gate reports CLEAN, the
  assertions in the diff have not been checked by anything.** Reading the test diff at the commit
  gate is what covers it, and that is a human step, not a mechanical one.
- Never `n=$(… | grep -c '^WEAKENED' || echo 0)` — `grep -c` prints `0` **and** exits 1 on no
  match, so `|| echo 0` appends a second line and `n` becomes the two-line string `0\n0`.

**SUSPECT findings (ADR-0051, issue #105) — advisory, non-blocking, extracted from the same
`$_wk` output.** `weakening-scan.sh` also emits a separate `SUSPECT<TAB><file><TAB><detector><TAB><line>`
sentinel for three heuristic reward-hacking detectors (`zero-assertion-test`,
`deleted-public-symbol`, `swallowed-error`). A fourth, `literal-assertion-added`, shipped disabled
and was retired on measurement — 0 true positives in 383 commits (#314, ADR-0144). `SUSPECT` never matches `^WEAKENED` and this gate must never grep for it as a
blocking condition — that promotion is exactly what ADR-0051 §D2 rejects:
```bash
if [ -n "$_wscan" ]; then
  _sus=$(printf '%s\n' "$_wk" | grep '^SUSPECT' || true)
fi
```
Record every `SUSPECT` line as a `{file, detector, line}` entry in `step5-report.json`'s
`suspect_findings` array (empty array if `_sus` is empty). Present the count and a per-detector
breakdown at Gate 5 (see the Gate 5 block in `## 5. HITL gates`) so a human reviewing the cycle
sees it — the finding is surfaced, never acted on automatically (ADR-0051 §D3).

**Policy:**
- Attended: present the `WEAKENED` findings and do NOT transition to `step_6_review` without user
  acknowledgment. `SUSPECT` findings are informational only — they never block this transition,
  they are simply carried forward into `suspect_findings` and shown at Gate 5.
- Autopilot (`manifest.autopilot = true`): halt on `WEAKENED` — do not transition, do not proceed
  to Gate 5. `SUSPECT` findings never halt autopilot either; they still populate
  `suspect_findings` for the eventual Gate 5 (or the autopilot report) to surface.
- `_wscan` empty (script did not resolve): record `"weakening_scan": "unavailable"` in
  `step5-report.json` and proceed — fail-open, visibly, per ADR-0047 §D2. `suspect_findings` is
  correspondingly absent (not malformed — the gate did not run).

#### Requirement-ID coverage gate — Step 5 → Step 6 (ADR-0048)

Checks that every requirement ID the SPEC declares is cited by a plan task and mentioned by a
test — the drift ADR-0048 exists to catch, invisible to every gate that only measures whether
the plan itself was executed.

**Resolution** (skill-helper path shape, `skills/concept-to-code/scripts/`, **not** `hooks/` —
`~/.claude` has two script locations and a resolution block copied from #100's reporters
resolves nothing here):
```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] \
   && [ -f "$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/spec-coverage.sh" ]; then
  _scov="$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/spec-coverage.sh"
elif [ -f "$HOME/.claude/skills/concept-to-code/scripts/spec-coverage.sh" ]; then
  _scov="$HOME/.claude/skills/concept-to-code/scripts/spec-coverage.sh"
else
  _scov=""     # gate did not run — report it, do not infer a clean result
fi
```

**Inputs:** `--spec <manifest.artifacts.spec>`, `--plan <manifest.artifacts.plan>`, and
`--tests-root <project_root>` — the project root, not a `tests/` guess, since discovery is by
basename. `--tests-root` is **omitted** when `manifest.test_cmd_placeholder = true` or
`manifest.test_cmd_provisional = true`: a project that has declared it has no test command, or
whose tests are still intent, cannot be held to test coverage (ADR-0018's "no test-cmd =
report-only mode", reused rather than reinvented).

**Invocation and exit-code idiom:**
```bash
# ADR-0133 §D1 (issue #394): the body between the two FENCE_BASH lines runs under BASH, not under
# the host shell, which is zsh here and differs from bash on word splitting, unmatched globs and
# `echo` escapes. That difference is load-bearing here — see the note on `${_troot:+…}` below.
# `export` forwards `_scov`, bound by the resolution block above; a plain shell variable does not
# survive the new process boundary. Terminator at COLUMN 0; an indented one is swallowed into the
# here-document and destroys this fence's exit code silently.
# NO `fence-contract` marker, deliberately (ADR-0133 §D3): this fence enters the wrapper population
# through the divergence SCANNER, not through a declaration. It cannot halt a run, so `F3` does not
# ask it for a marker, and adding one would create an `F4` execution obligation this feature did not
# budget. The absence is a decision, not an oversight. (This note deliberately avoids the standalone
# word for halting: `fence_is_abort_capable` matches it as a whole word, so a comment SAYING this
# fence cannot halt would classify it as one that can — rule 12, in the sentence written to explain
# the missing marker.)
export _scov
bash <<'FENCE_BASH'
if [ -n "$_scov" ]; then
  _troot=""
  if [ "<manifest.test_cmd_placeholder>" != "true" ] && [ "<manifest.test_cmd_provisional>" != "true" ]; then
    _troot="<project_root>"
  fi
  # `${_troot:+--tests-root "$_troot"}` expands to TWO words, and that is guaranteed by the wrapper
  # above (issue #394, ADR-0133): bash word-splits the expansion, zsh does not. Measured on a live
  # fixture under both shells: wrapped, this returns the real verdict identically under zsh and bash;
  # unwrapped under zsh the option arrived as the SINGLE argument `--tests-root <path>`,
  # `spec-coverage.sh` reported `unknown argument` and exited 2 — and `_rc = 2` is this gate's
  # fail-open branch, so ADR-0048's merge-blocking requirement-coverage gate was not merely fed an
  # unreadable token, it was passing every time a tests-root was supplied. Do not "fix" this by
  # quoting the expansion: the point of the `:+` form is that it expands to NOTHING when `_troot` is
  # empty, and quoting would pass one empty argument in its place.
  _out=$(bash "$_scov" --spec "<manifest.artifacts.spec>" --plan "<manifest.artifacts.plan>" ${_troot:+--tests-root "$_troot"} 2>&1)
  _rc=$?
  # ADR-0133 §D4: this body runs in a SUBPROCESS, so `_troot`, `_out` and `_rc` die at the
  # terminator below — and the self-repair retry block further down reads all three. They are
  # printed values now: the `SPEC-COVERAGE:` line is authoritative, and the orchestrator carries
  # `rc` and `troot` forward exactly as it carries `<manifest.artifacts.plan>` into this block.
  # `_out` is everything printed after that line. Before the wrapper the two blocks received these
  # values from each other only because they happened to share a shell — an implicit inter-block
  # dependency nothing documented.
  printf 'SPEC-COVERAGE: rc=%s troot=%s\n' "$_rc" "$_troot"
  printf '%s\n' "$_out"
fi
FENCE_BASH
```
**What this block hands on (ADR-0133 §D4).** The wrapper runs the body in a subprocess, so `_troot`,
`_out` and `_rc` do not survive the terminator. The `SPEC-COVERAGE:` line is authoritative: carry
`rc` and `troot` from it, and read `_out` as everything printed after it. The self-repair block below
declares the same three plus `_scov` as orchestrator-bound for that reason — before the wrapper they
reached it only because the two blocks happened to share a shell, an inter-block dependency nothing
documented. No `SPEC-COVERAGE:` line at all means `_scov` was empty and the gate did not run, which
is the fail-open case already described below, not a clean result.

`_rc = 0` → every declared ID covered, or the SPEC declares no IDs. `_rc = 1` → at least one ID
uncovered or unscoped, `_out` names the ID and the missing half (`plan`, `tests`, or `plan,tests`)
— that is `UNCOVERED<TAB>id<TAB>missing` — or `UNSCOPED<TAB>id<TAB><scope-size>`: the id is
mentioned somewhere in the discovered test population but not in a file the plan names, a
**distinct remedy from `UNCOVERED`'s "write a test"**: cite the id in the test file this feature
actually wrote, rather than write a new one (ADR-0138 §D3). `_rc = 3` → structural error in the
SPEC or plan (`DUPLICATE`/`MALFORMED`/`ORPHAN` in `_out`, remedy: fix the artifact, not write a
task) or `STALE-WAIVER<TAB>id` — a `(no-test: …)` exemption whose id IS found in the scoped test
set; the remedy is deleting the `(no-test: …)` clause from the SPEC, and this one is **not**
auto-repaired, unlike the plain-bullet near-miss below (ADR-0138 §D4). `_rc = 2`, or `_scov`
empty → treat as unavailable, fail-open (see Policy).

**Self-repair on the one structural error that has a mechanical fix (ADR-0072 §D3, issue #171).**
Before treating `_rc = 3` as a stop, check whether the cause is the plain-bullet form — requirement
ids declared as `- R-01 — …` instead of `- [ ] R-01 — …`. It is the only structural error whose
repair is deterministic: the two lines say the same thing and only the second is one the checker
reads, so adding the marker changes no content.

```bash
# ADR-0133 §D1 (issue #394): the body between the two FENCE_BASH lines runs under BASH, not under
# the host shell, which is zsh here and differs from bash on word splitting, unmatched globs and
# `echo` escapes — see the `${_troot:+…}` note in the invocation block above, which applies verbatim
# to the re-run below. Terminator at COLUMN 0; an indented one is swallowed into the here-document
# and destroys this fence's exit code silently.
# Free variables, bound by the orchestrator from the invocation block's `SPEC-COVERAGE:` line and
# from the resolution block above it: `_rc`, `_out`, `_troot`, `_scov` (ADR-0133 §D4). That block
# runs in its own subprocess, so these do NOT arrive through a shared shell; the orchestrator
# carries them, exactly as it carries `<manifest.artifacts.spec>`.
# NO `fence-contract` marker, deliberately (ADR-0133 §D3): scanner-derived population member, and it
# cannot halt a run, so no `F3` obligation and no `F4` execution obligation is created here. The
# standalone word for halting is avoided on purpose — `fence_is_abort_capable` matches it as a whole
# word, so writing it here would classify this fence as one that can halt (rule 12).
export _rc _out _troot _scov
bash <<'FENCE_BASH'
if [ "$_rc" -eq 3 ] && printf '%s\n' "$_out" | grep -q 'declared as plain bullets'; then
  _norm="$(dirname "$_scov")/spec-normalize-ids.sh"
  if [ -f "$_norm" ]; then
    _diff=$(bash "$_norm" --spec "<manifest.artifacts.spec>" --apply); _nrc=$?
    # §D4: `_diff` dies at the terminator too, so the block emits it under the heading the
    # paragraph below mandates, rather than leaving the orchestrator to read a variable that no
    # longer exists. It goes FIRST so the ordering contract stays simple: the repair diff, then the
    # re-run verdict, and everything after the `SPEC-COVERAGE:` line is `_out`.
    printf 'Requirement ids: repaired plain-bullet declaration(s) — diff:\n'
    printf '%s\n' "$_diff"
    if [ "$_nrc" -eq 0 ]; then
      _out=$(bash "$_scov" --spec "<manifest.artifacts.spec>" --plan "<manifest.artifacts.plan>" ${_troot:+--tests-root "$_troot"} 2>&1)
      _rc=$?
      # The re-run's verdict must leave this subprocess the same way the first one did, or the gate
      # below reads the PRE-repair `_rc` and stops on an error that has already been fixed.
      printf 'SPEC-COVERAGE: rc=%s troot=%s\n' "$_rc" "$_troot"
      printf '%s\n' "$_out"
    fi
  fi
fi
FENCE_BASH
```

**Apply first, show after — do not gate this.** The edit is mechanical, and ADR-0071's Gate 4.0 has
already committed the planning artifacts, so `git checkout -- <spec>` reverses it. Stopping a chain
to ask permission for a checkbox marker is friction with one sensible answer, and on the unattended
paths it would be a halt with no one to answer. The block emits the diff `spec-normalize-ids.sh`
returned under the heading `"Requirement ids: repaired plain-bullet declaration(s) — diff:"` — it
prints the heading itself rather than binding a `_diff` variable, because under the ADR-0133 wrapper
that variable dies at the terminator. Surface both lines to the user, so the edit is visible after
the fact rather than invisible.

If this block prints a second `SPEC-COVERAGE:` line, it supersedes the first: it carries the
**post-repair** `rc`, and `_out` is again everything after it. If it prints none, nothing was
repaired and the first verdict stands. If the re-run still returns 3, stop as before: the cause was
something else, or something the repair does not cover. **A bold-wrapped id (`- **R-01** — …`) is no longer one of those (ADR-0122, issue
#291).** In a checklist item it reads as declared directly, no repair needed. As a plain bullet it
is a near-miss like any other and is repaired by this same automatic path, with the emphasis
preserved — `- **R-01** — …` becomes `- [ ] **R-01** — …`, never stripped. Never loop: the repair
runs at most once per gate invocation.

**This gate branches on the exit code. The anti-test-weakening gate immediately above must
never do that — `weakening-scan.sh` always exits 0 and signals through stdout. Two adjacent
gates, two idioms, on purpose: `spec-coverage.sh` is a checker with an exit-code contract,
`weakening-scan.sh` is a reporter that never decides policy.**

**Do not copy one block's branching into the other.**

**Cadence:** this gate runs once at the Step 5 exit, not at every batch checkpoint, unlike the
anti-test-weakening gate above. Mid-run, an uncovered ID is the expected state — a task that has
not executed yet legitimately leaves the ID it satisfies uncovered, and running this gate per
batch would fail on every multi-batch chain.

**Policy:**
- Attended: present the uncovered IDs (`_rc = 1`) or the structural error (`_rc = 3`) and do NOT
  transition to `step_6_review` without user acknowledgment.
- Autopilot (`manifest.autopilot = true`): halt — do not transition, do not proceed to Gate 5.
- `_rc = 2`, or `_scov` empty (script did not resolve): fail-open, visibly. Record
  `"status": "unavailable"` in `step5-report.json` and proceed.

#### Diff budget and scope check — Step 5 checkpoints (ADR-0052)

Compares what a coder's diff actually touched against what the plan said it would, at the same
checkpoints the anti-test-weakening gate above already visits (§D2 — no new checkpoint
mechanism). Purely advisory, and inert unless the architect declared a budget: a per-task line
ceiling is an estimate made before the work by an agent that has not read every file it will
touch, so it surfaces and never blocks (§D3).

**Resolution** (skill-helper path shape, `skills/concept-to-code/scripts/`, the same two-location
trap `spec-coverage.sh` above avoids):
```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] \
   && [ -f "$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/diff-budget-check.sh" ]; then
  _dbudget="$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/diff-budget-check.sh"
elif [ -f "$HOME/.claude/skills/concept-to-code/scripts/diff-budget-check.sh" ]; then
  _dbudget="$HOME/.claude/skills/concept-to-code/scripts/diff-budget-check.sh"
else
  _dbudget=""     # check did not run — report it, do not infer a clean result
fi
```

**Invocation and caller idiom.** `diff-budget-check.sh` is a REPORTER, exactly like
`weakening-scan.sh` above and unlike `spec-coverage.sh` immediately above this block: it always
exits 0 and signals through stdout, printing the sentinel `CLEAN` when there is nothing to
report. **Do not copy `spec-coverage.sh`'s branch-on-exit-code idiom into this block** — that
sentence has now been written three times in this directory (ADR-0048 §D7, the anti-test-
weakening gate above, and here).
```bash
if [ -n "$_dbudget" ]; then
  # --stat=999, never a bare --stat — git elides long paths at 80 columns (ADR-0070 §D5).
  _db=$(git diff --stat=999 "$_pre5" 2>/dev/null \
        | bash "$_dbudget" --plan "<manifest.artifacts.plan>" --tasks "<comma list of every task number dispatched so far>")
fi
```
- Never `[ -n "$_db" ]` to decide whether something was found — `$_db` is the literal string
  `CLEAN` on a clean run, never empty.
- Never `n=$(printf '%s\n' "$_db" | grep -c '^BUDGET' || echo 0)` — `grep -c` prints `0` **and**
  exits 1 on no match, so `|| echo 0` appends a second line and `n` becomes the two-line string
  `0\n0`. Use `grep -c '^BUDGET' || true` if a count is needed.
- **A third token exists: `MALFORMED<TAB>task <N><TAB><declaration text>` (issue #246).** It means
  the checker found a recognisable budget declaration it could **not read** — not that the task
  overspent, and not that it declared nothing. Surface it to the human at Gate 5 with the task
  number and the offending text, and say plainly that this task's budget was **not measured**. A
  token the caller drops is a producer with no consumer, which is the defect class #238 records;
  do not leave it unread just because it is advisory.

**Cadence, matching the anti-test-weakening gate above (§D2 — no new checkpoint mechanism, reusing
the same one).** The Workflow dispatch path runs this once, after the whole workflow completes,
over the cumulative diff since `$_pre5` and every task in `tasks_completed` from
`step5-report.json` — for the same reason the weakening gate above runs once there rather than per
pipeline stage: the orchestrator only regains control after the workflow exits. The Agent-tool
fallback runs it at every batch checkpoint (see step 4 there), `--tasks` accumulating every task
dispatched so far, against the same cumulative diff the weakening gate already re-scans at that
point.

**Record every `MALFORMED` line as its own entry in the same array**, `{task, malformed}` — the
declaration text verbatim, no `files_*` or `lines_*` keys, because nothing was measured and writing
zeros there would read as a task that spent nothing. Additive, no schema bump, the same terms as
every prior extension of this file.

**Record every `BUDGET` line's `files=<exp>/<act>` and `lines=<exp>/<act>`, and every `SCOPE`
line's file, as one entry per checkpoint call** in `step5-report.json`'s `budget_findings` array
(`{task, files_expected, files_actual, lines_expected, lines_actual, out_of_scope}` — `out_of_scope`
collects that call's `SCOPE` file names; the plan-level scope check has no single owning task to
attribute a `SCOPE` finding to, so it rides on the same checkpoint entry). Empty array if `$_db`
is `CLEAN`.

**Policy:**
- `budget_findings` is **never a failure signal**, attended or under autopilot (ADR-0052 §D3) —
  it never blocks the transition to `step_6_review`. Findings are carried into `budget_findings`
  and folded into the Gate 5 roll-up (ADR-0052 §D5, see the Gate 5 block in `## 5. HITL gates`).
- `_dbudget` empty (script did not resolve): record no `budget_findings` entries for that
  checkpoint and proceed — fail-open, visibly, matching the weakening gate's own
  `"weakening_scan": "unavailable"` idiom.

#### Task-level metrics — Step 5 checkpoints (ADR-0064, issue #118)

**These are METRICS, not findings (ADR-0064 §D2).** A finding asserts something is wrong and asks
for a decision; a metric is a number with no claim attached. This block is not surfaced at Gate 5,
is not counted in the advisory roll-up below, and is not presented as actionable — it feeds
`task_metrics` in `step5-report.json` only, for the analysis rut detection and trust scoring will
eventually need (ADR-0064 §A5: no such detector or threshold exists yet, and building one against
an empty corpus would mean inventing a threshold rather than measuring one — this feature builds
the inputs only). Runs at the same checkpoints as the two blocks immediately above (§D2 of both
ADR-0047 and ADR-0052 — no third checkpoint mechanism): once after the Workflow path completes,
once per batch checkpoint in the Agent-tool fallback below.

**Every field is computed, never self-reported (ADR-0064 §D4).** None of the four fields is
requested in any tester or coder dispatch prompt in this Step, and no dispatch template below asks
an agent to report an iteration count, an elapsed time, a test count, or a line count — each of
the four is produced independently by the orchestrator from `git` output or from its own dispatch
bookkeeping.

**Resolution** (skill-helper path shape, `skills/concept-to-code/scripts/`, the same two-location
pattern `spec-coverage.sh` and `diff-budget-check.sh` above use):
```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] \
   && [ -f "$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/agent-metrics.sh" ]; then
  _ametrics="$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/agent-metrics.sh"
elif [ -f "$HOME/.claude/skills/concept-to-code/scripts/agent-metrics.sh" ]; then
  _ametrics="$HOME/.claude/skills/concept-to-code/scripts/agent-metrics.sh"
else
  _ametrics=""     # did not resolve — OMIT test_count_delta and deleted_lines from this
                    # checkpoint's entry, do NOT invoke the script and default its output to 0
fi
```

**`test_count_delta` and `deleted_lines` — from `git`, via `agent-metrics.sh`.** The script reads
the SAME full unified diff already piped into the anti-test-weakening gate above (`git diff
"$_pre5"`, not a second git call, not `--stat`/`--numstat`) and always prints two TAB-separated
lines, `DELETED_LINES` and `TEST_COUNT_DELTA`:
```bash
if [ -n "$_ametrics" ]; then
  _am=$(git diff "$_pre5" 2>/dev/null | bash "$_ametrics" 2>/dev/null)
  # The trailing `[[:space:]][[:space:]]*` requires at least one separator, so a longer token
  # (`DELETED_LINES_X`) cannot satisfy the shorter one's pattern. A negative TEST_COUNT_DELTA
  # survives: the substitution removes only the token and the separator run.
  _dl=$(printf '%s\n' "$_am" | sed -n 's/^DELETED_LINES[[:space:]][[:space:]]*//p')
  _tcd=$(printf '%s\n' "$_am" | sed -n 's/^TEST_COUNT_DELTA[[:space:]][[:space:]]*//p')
fi
```
If `_ametrics` is empty, or `_dl`/`_tcd` fail to parse as an integer, OMIT that field from this
checkpoint's `task_metrics` entry — never write `0` in its place (ADR-0064 §D3). A genuinely
empty diff (nothing changed since `$_pre5`) is a real, computed zero and IS written as `0` — the
distinction is between "the script ran and measured zero" and "the script did not run", not
between "zero" and "nonzero".

`agent-metrics.sh`'s test-file predicate is reused verbatim from `test-write-scope.sh` (ADR-0049
§D4 — the "broad union minus `.md`" DENIAL predicate), not `spec-coverage.sh`'s narrower DISCOVERY
predicate in the same directory, even though both already exist and could be reused. ADR-0049 §D4
records that the two diverge on purpose: a discovery predicate must not over-match (a false
coverage pass), a denial predicate must not under-match (a missed test path is invisible).
Counting tests shares the denial predicate's failure direction — a test file this predicate
silently missed would make a real test-count drop invisible in this metric, which is exactly the
kind of quietly-manufactured well-behaved-looking task ADR-0064 §D3 already warns against, just
reached through under-matching instead of zero-defaulting. The narrower discovery predicate was
rejected for that reason, not reused.

**`iteration_count` and `elapsed_wall_seconds` — from the dispatch loop, no script.** Before the
first dispatch in this Step, alongside `_pre5=$(git rev-parse HEAD)`, also record
`_pre5_ts=$(date -u +%s)`. At each checkpoint:
- `elapsed_wall_seconds` = `$(date -u +%s)` at the checkpoint minus `$_pre5_ts` — cumulative since
  Step 5 began, the same cumulative-since-`$_pre5` convention `budget_findings` and the weakening
  gate already use. This measures wall-clock time, not agent effort — it includes queueing, rate
  limiting, and anything else in the way (ADR-0064 negative consequence, stated here rather than
  only in the ADR: do not read this figure as effort).
- `iteration_count` = the cumulative count of agent dispatches issued so far in this Step for the
  tasks in this checkpoint's `task` label — stage count, not retry count: a task group dispatched
  as tester → coder is 2, tester → coder → reviewer under `step5_review_mode: checkpoint` is 3.
  There is no per-task retry loop in this Step to count instead; do not invent one to make this
  figure mean something it does not measure.
If `_pre5_ts` was never recorded (e.g. a resumed session that skipped the pre-flight block above),
OMIT `elapsed_wall_seconds` for every checkpoint in that run rather than measuring from an
arbitrary later point.

**Record one `task_metrics` entry per checkpoint**, tagged with the same `task` label
`budget_findings` uses at that same checkpoint (a single task number, or the comma list / range of
every task dispatched so far), carrying whichever of the four fields were actually computed.

#### Fallback — Agent-tool batch dispatch (hook_verified = false or workflow unavailable)

**Batch boundaries are a design choice, not an arithmetic one (ADR-0088, issue #241).** The tester
runs once per batch, before the coder, so an assertion that depends on another task's output cannot
see it if both sit in the same batch — the merge-back that would make it visible happens at the
batch boundary. Two rules follow, and reading the plan is the only way to apply them: do not put an
assertion in the same batch as the task it depends on, and do not split a red assertion from the
task that turns it green. #222's plan is the worked example — Task 3's `C7` must see Task 2's
vendored file, so they belong to different batches, while Task 1's `F10` and Task 2's vendoring
belong to the same one.

**When the two conflict, the first rule outranks the second (issue #247, ADR-0101).** They are not
jointly satisfiable on every plan, and #222's is the case: rule 1 forces task 3 into a later batch
than task 2, while rule 2 wants them together because `S1` reddens at task 2 and greens at task 3.
The reason for the ordering, and it is the part to carry forward rather than the verdict:
**evidence quality beats checkpoint tidiness.** Violating rule 1 makes an assertion fail for the
wrong reason, so the recorded RED proves nothing and the whole point of writing the test first is
gone. Violating rule 2 only leaves an intermediate checkpoint red — visible, explainable, and
resolved by a later batch in the same Step 5.

**A third rule, and on a compiled or type-checked language it outranks both (issue #486,
ADR-0155).** The tester's batch must leave the target BUILDING. The interface or type declaration
its tests reference lands with the tests, not with the implementation: **the tester owns the
signature, the coder owns the body.**

The two rules above assume something nobody wrote down until #486 — that a failing assertion still
compiles. In bash it does: the harness runs, prints `FAIL: <id>`, and the observed failing set can
be compared against the plan's expected-red table. In Swift, Rust, Go or TypeScript under
`tsc --noEmit` it does not. A test referencing a type the coder has not written yet does not fail;
it stops the target from building, and then nothing runs at all. Measured on a live run against a
Swift project on 2026-08-18: `cannot find type 'GoogleBooksAPIKeyStoring' in scope`, followed by
`Testing cancelled because the build failed`.

**Its precedence, in the same terms the tie-break above uses.** Violating rule 1 makes an assertion
fail for the wrong reason, so the recorded RED proves nothing. Violating this one means there is no
recorded RED at all, and no checkpoint state describing what happened — a strictly larger loss, and
why it is a precondition rather than a third peer.

**It does not weaken the generator/verifier separation (ADR-0155 §D2).** What ADR-0049 buys is that
tests are written without seeing the implementation, and a protocol or type declaration is not an
implementation — it is the interface, the same vocabulary ADR-0053's protected-interfaces already
uses. Nothing in the hook layer had to change for this: `test-write-scope.sh` constrains the coder
only, so it **already permits** the tester to write the declaration (ADR-0155 §D6). What was missing
was anything telling it to.

**This is an instruction, not an enforcement (rule 16), and nothing here blocks a dispatch.** No
hook checks that a plan placed the declaration in the tester's task; `test-write-scope.sh` already
permits it either way. What is enforced is that this rule is written down, and the consequence when
it is ignored is the fourth checkpoint state below.

**Batch-dispatch policy (≥6 task blocks in plan):** **the number is `$openers`, from
`plan-tasks.sh --count-openers`, never `$tasks` (issue #242, ADR-0100).** `$tasks` over-counts by
design — a `## Tasks` section heading and every checkbox sub-step match it — so batching by it
produces ranges over tasks that do not exist; on #222's plan it says 38 where there are 7.

If `$openers ≥ 6`, do NOT dispatch the coder as a single monolithic block — the dispatch can
silently truncate halfway (context overflow, timeout) without a final report and without running
the closing gates. Split the dispatch into **batches of 2-3 task blocks**, numbered by their
`Task N` designations.

**If `$openers = 0` while `$tasks ≥ 1`: dispatch as a single block**, and say so:
> "Batch dispatch: the plan's tasks are not in the `Task N` form (`plan-tasks.sh --count-openers`
> returned 0), so batch ranges cannot be numbered. Dispatching as one block."

Two corpus plans, not three shapes, are in exactly that state — `deep-refactor-skill.md` (which
writes `### T1 —`) and `claude-md-slim.md` (which writes `### Step N —`, whose first heading is
`### Step 0 —`), the forms ADR-0070 §PTG9 and ADR-0069 §PTE2 exempt by name. Consuming `$openers`
without this branch would turn an over-batching bug into a batch-nothing one, which is #242
committed in the other direction.
If `$orc` is 2 or 3 the count did not run: treat it as this same case, single block, and report the
stderr.

1. Dispatch `tester` for batch 1 (tasks 1-N, where N ≤ 3), BEFORE this batch's coder
   (ADR-0049 §D1 — same ordering as the Workflow path's Stage 1). Pin `subagent_type: "tester"`,
   `model: "sonnet"`, and `isolation: "worktree"` explicitly (ADR-0049 §D6; `tester` has no
   `isolation` in its own frontmatter, F5, so an omitted value here means no worktree at all,
   ADR-0068 §D6, R-09). Do not pin `effort` here — the Agent tool has no such parameter at all
   (ADR-0068 §D7, issue #180); the effort table above documents the Workflow path's per-agent
   calibration only, not a value to carry over to this dispatch. Use the **Tester batch dispatch
   template** below — same brief contract as the Workflow path: SPEC requirement IDs via
   `spec-coverage.sh --list`, falling back to Success Criteria then to this batch's plan task
   text, never from implementation files.
2. Dispatch coder with batch 1 (tasks 1-N, where N ≤ 3). Before this dispatch, run the
   **Merge-back and base-fork audit** block above to merge this batch's tester worktree into the
   feature branch (same resolution site, same ordering as the Workflow path's Stage 1 → Stage 2).
   Pin `isolation: "worktree"` explicitly (ADR-0068 §D1, §D7 — there is no second mode; per the
   merge-back step just run, this coder forks from a `HEAD` that already contains the batch's
   failing tests) and use the **Single batch dispatch template** below, which carries the
   TEST-AUTHORING SCOPE marker verbatim.

   **After this coder's dispatch completes (the notification arrives), read its completion fact
   (below) BEFORE running its own merge-back (issue #494, ADR-0159).** `$WT` is already known at
   this point — from the dispatch result (F10) or by enumeration (F19/F20) — and nothing has
   touched that worktree yet. Only on the `complete` line does the **Merge-back and base-fork
   audit** block above run again, this time to merge THIS batch's coder worktree into the feature
   branch; its own final step, `git worktree remove "$WT"`, is what deletes the root the completion
   fact lives under, so the read must come first. A `HALT` line here means the worktree is left
   exactly as it is: not merged, not removed.
3. Checkpoint between batches: run
   `bash $HOME/.claude/skills/review-triage-fix/scripts/verify.sh <root>` (issue #411 — a bare
   `verify.sh` is on no `PATH`) and check `git status` yourself
   as the orchestrator — do NOT trust the coder's report to decide whether to continue
   (it may be truncated or incomplete). Also run the `Anti-test-weakening gate — Step 5 →
   Step 6 (ADR-0047)` block at every batch checkpoint — the same command against the same
   cumulative diff, evaluated at more points, so an unattended run that weakens a test in
   batch 1 halts before burning batches 2..N. Also run the `Diff budget and scope check —
   Step 5 checkpoints (ADR-0052)` block at every batch checkpoint, `--tasks` accumulating
   every task number dispatched so far — advisory only, never a gate here either. Also run the
   `Task-level metrics — Step 5 checkpoints (ADR-0064, issue #118)` block at every batch
   checkpoint — metrics, not findings; never a gate, never surfaced at Gate 5.

   **An intermediate checkpoint can be legitimately red, and the chain had no concept of that until
   issue #247 (ADR-0101).** ADR-0049's flow assumes the tester reddens and the coder greens *within
   the same batch*, so a checkpoint should be clean. A third case exists: a **pre-existing guard in
   a file nobody in this batch touched**, whose premise the implementation changes and which a later
   task restores. #222's `S1` is the worked example — it reddens when task 2 vendors a skill into
   the population and greens when task 3 covers it, and the SPEC predicted it in those words.

   When a checkpoint is red, classify before reacting. **A red in a file this batch did not touch,
   which a later task in the plan restores, is expected**: name it, name the task that will green
   it, record it, and continue. **A red in this batch's own tests is not expected** and is the case
   the checkpoint exists for — stop and report. If neither description fits, stop: an unclassifiable
   red is the one that most needs a human.

   **A fourth state exists and it is not a red at all: THE TARGET DID NOT BUILD (issue #486,
   ADR-0155 §D4).** On a compiled or type-checked language a checkpoint can produce no test result
   whatsoever — `Testing cancelled because the build failed`, and no assertion ran. Do not classify
   it as an unclassifiable red: the two look identical in a transcript and they have opposite
   remedies. Its meaning is specific — **the third batch-boundary rule above was violated**, the
   interface declaration the tests reference did not land in the tester's batch — and so is its
   remedy: correct the batching, not the code under test. Nothing here needs debugging.

   The distinction is worth the paragraph because collapsing it is what makes an operator stop
   reading the section. In this state the expected-red table cannot be checked at all, the
   controller-side count read has nothing to read, and a genuine regression the coder introduced in
   an already-green area produces the same output as the intended state.

   This is a reading rule, not a mechanism. An **expected-red declaration** in the plan, or a
   comparison against the previous checkpoint's failing set, would let the checkpoint decide rather
   than the reader — both were considered and deferred: the first needs a plan-side syntax, and
   issue #246 is the live warning about what a half-parsed one costs. `autopilot-build`'s circuit
   breaker is deliberately NOT relaxed in the meantime; it reads `step5-report.json` once after
   dispatch, so a red that greens inside Step 5 never reaches it.

   <!-- dispatch-site: step5-checkpoint-reviewer class=inline exempt: the reviewer grant carries no Write tool so no completion fact is producible, and its findings are carried forward as advice that halts nothing -->
   **[IF `manifest.step5_review_mode = checkpoint` (ADR-0039 D5-D9) — otherwise skip:]**
   At this same checkpoint, dispatch the `reviewer` agent scoped to the diff of the batch that
   just closed. It reviews only and fixes nothing: this is where the Workflow path would run its
   pipeline review stage, and the two paths must reach the same place. Carry the BLOCKER and
   MAJOR findings into the brief of the next batch as "found in batch <N>, do not repeat this".
   MINOR and NIT are recorded and left for Step 6, where RTF runs the full cycle over the whole
   diff. Record each review in `checkpoint_reviews` in `step5-report.json`.
   A finding here never halts the chain — it is feedback for the next batch, not a gate.
   If a dispatch returns without output or hangs unexpectedly, run:
   `claude agents --json | jq '.[] | select(.waitingFor != null) | {id, waitingFor}'`
   A non-null `waitingFor` means the coder is blocked on a permission prompt —
   surface it to the user rather than waiting in silence (CC 2.1.162+).
4. Repeat steps 1-2 (tester, then coder) for batch 2 (tasks N+1…), and so
   on.
5. After the last batch: run the `Anti-test-weakening gate — Step 5 → Step 6 (ADR-0047)`
   block again, and run the `Requirement-ID coverage gate — Step 5 → Step 6 (ADR-0048)`
   block once here too — not at the per-batch checkpoint in item 3 above, where an
   uncovered ID is still the expected state — then final verification
   (`bash $HOME/.claude/skills/review-triage-fix/scripts/verify.sh <root>`, `git status`, scope
   check against the plan) before transitioning to `step_6_review`.
   The `Diff budget and scope check — Step 5 checkpoints (ADR-0052)` block already ran at
   every batch checkpoint in item 3; no separate final pass is needed for it. Same for the
   `Task-level metrics — Step 5 checkpoints (ADR-0064, issue #118)` block.

For plans with ≤5 tasks monolithic dispatch is acceptable, but the controller-side
verification after dispatch is mandatory in all cases.

**Coder model override:** if `manifest.coder_model = "opus"` (or legacy `"fable"`), pass `model: "opus"` to every `Agent(subagent_type="coder", ...)` call in this dispatch. If `sonnet` or null, omit the `model` parameter (global coder.md applies).

<!-- dispatch-site: step5-batch-tester class=isolated exempt: its completion is already gated by the merge-back block that must run before the coder forks, so an early advance conflicts rather than passes -->
**Tester batch dispatch template** (dispatched BEFORE this batch's coder — ADR-0049 §D1; pin
`subagent_type: "tester"` and `model: "sonnet"` explicitly on this `Agent` call, ADR-0049 §D6; no
`effort` pin — the Agent tool has no such parameter, ADR-0068 §D7, issue #180):
```
Read plan at <manifest.artifacts.plan> (tasks <FROM>-<TO> only).
Read SPEC.md at <manifest.artifacts.spec>.

Write failing tests for tasks <FROM>-<TO> only. Brief yourself from the SPEC's requirement IDs:
run `spec-coverage.sh --spec <manifest.artifacts.spec> --plan <manifest.artifacts.plan> --list`
(resolved exactly as in the Requirement-ID coverage gate below). If it lists one or more `R-NN`
IDs, write one failing test per listed ID this batch covers. Else if the SPEC declares no IDs,
brief from the SPEC's Success Criteria section verbatim. Else, brief from this batch's plan task
text. Never brief from implementation files — none exists yet for this batch.

That chain decides WHAT to assert. The plan decides WHERE and under what name, and you read it in
every case — never as a fallback. Work through tasks <FROM>-<TO> sub-step by sub-step and execute
every sub-step that creates or edits a test file. Those sub-steps are yours: the coder dispatched
after you is denied them by a PreToolUse gate, so a skipped sub-step is a sub-step nobody can do.
Where a sub-step says to confirm a failing assertion and stop, stop — a red assertion left red is
the deliverable, not an unfinished task.

On a compiled or type-checked language, leave the target BUILDING (ADR-0155 §D1). Declare the
interfaces, protocols or types your tests reference but which do not exist yet — the signature is
yours, and the coder owns the body. A test naming a type nobody has written does not fail, it stops the
target from compiling, and then no assertion runs at all and the red you were dispatched to produce
does not exist. Declaring an interface is not implementing it: you are writing the boundary the
specification already fixes, not the code that satisfies it. `test-write-scope.sh` constrains the
coder only, so nothing blocks you from writing that declaration on a production path.

Writes go under the dispatched worktree, never to an absolute path into the shared checkout: `isolation: worktree` bounds the working directory, not the filesystem, and an absolute path resolves out of it (ADR-0068 §D11, issue #245). Read the planning artifacts by absolute path; write by relative path.

Auto mode active. No intermediate HITL.
Return a report naming the requirement IDs (or Success Criteria / plan-task lines, per whichever
fallback fired) each test covers, plus which sub-steps you executed and which you leave to the
coder.
```

**Single batch dispatch template** (dispatched AFTER this batch's tester above; MUST carry the
TEST-AUTHORING SCOPE marker verbatim, ASCII hyphen, ADR-0049 §D3):
```
Read plan at <manifest.artifacts.plan> (tasks <FROM>-<TO> only).
Read ADR at <manifest.artifacts.adr>.
Read SPEC.md at <manifest.artifacts.spec>.
Read project CLAUDE.md at <manifest.artifacts.project_claude_md> (if not null).

TEST-AUTHORING SCOPE - the tester agent owns test files for this task. Do NOT create or edit tests.
Sub-steps in your tasks that create or edit test files were executed by the tester before this
dispatch and are NOT yours. Do not repeat them and do not edit those files. If that leaves a task
looking incomplete, say so in your report rather than closing the gap yourself. Make the red tests
green, except where the plan defers a red assertion to a later task: an assertion the plan defers
to a later task stays red, and your report says which one and why.
The red tests for tasks <FROM>-<TO> already exist — the tester agent wrote them before this
dispatch. You may not create or edit test files; if a test needs changing,
report it to the orchestrator instead of writing or editing it yourself.
Use your Pre-flight Pattern Classifier (ADR-0001) for every Edit operation.

Writes go under the dispatched worktree, never to an absolute path into the shared checkout: `isolation: worktree` bounds the working directory, not the filesystem, and an absolute path resolves out of it (ADR-0068 §D11, issue #245). Read the planning artifacts by absolute path; write by relative path.

Auto mode active. No intermediate HITL.
`.claude/test-cmd` is off-limits — never read, write, or modify it. If the test command needs changing, stop and report it to the orchestrator.

[IF manifest.license != null AND manifest.license != "None" — add this line to dispatch, otherwise omit:]
LICENSE FILE: Ensure a LICENSE file exists at the project root matching the declared license (<manifest.license>). Create it if absent; do not modify if present.

[IF manifest.xcode_project=true — add this line to dispatch, otherwise omit:]
XCODE SCAFFOLD: Execute the Xcode project scaffold task from the plan (Swift 6, SwiftUI structure, Package.swift or .xcodeproj, target config, bundle ID) as part of this batch if included in tasks <FROM>-<TO>.

[IF manifest.anonymize=true — add this block to dispatch, otherwise omit:]
Anonymize mode: ON (ADR-0011).
- Commit messages in Conventional Commits: minimal subject + body. No tool trailers
  (e.g., "Co-Authored-By: Claude", "Generated with Claude Code") — already off via
  settings.json, reiterated here.
- No trace comments in code: no "// added by Claude", AI/task references, generated TODOs.
  Only comments a human author would write.
- No file slop: only files required by the plan (no redundant READMEs, scratch files, notes).
- No decorative emoji unless requested. Concise and technical docs.

Return a report with: tasks completed (list), files modified, test results, harness deltas.

As your LAST action, before returning anything, write the completion fact into your OWN worktree:

    mkdir -p .claude/dispatch && printf 'tasks=%s files=%s\n' <N> <M> > .claude/dispatch/step5-batch-<B>.done

where N = tasks completed, M = files modified, B = this batch's number. Write it with literal
numbers, not shell variables. This file is what the controller reads; a report that ends without it
is treated as an unfinished dispatch no matter what the report says.

Also end the report with `PATTERN: DONE tasks=<N> files=<M>` — that line is for a human reading the
transcript and nothing branches on it.
```

<!-- dispatch-site: step5-batch-coder class=isolated -->
After each batch's coder dispatch completes, read the batch's completion fact — **before running
that coder's own merge-back**, and before running controller-side verification, which needs the
merge-back to have happened first. **Do not look for `PATTERN: DONE` in the agent's report.** Since
CC 2.1.232 a non-teammate `Agent` dispatch returns immediately with metadata only and the report
arrives later as a notification, so the tool result never carries that line and a healthy dispatch
reads as truncated (issue #435, ADR-0139). The coder writes the fact inside its own worktree and
`$WT` — bound at dispatch (F10) or by enumeration (F19/F20), NOT by the merge-back block, whose own
final step deletes this root on success (issue #494, ADR-0159) — is the root that holds it:

<!-- fence-contract: step5-batch-completion-gate -->
```bash
# ADR-0133 §D1 (issue #394): the body below runs under BASH, not the host shell, and the heredoc is
# QUOTED — so nothing in it expands here. `export` is what carries the caller-bound values in, the
# same device check 6 of autopilot-build uses. WT is the worktree path bound at this batch's coder
# dispatch (F10) or by enumeration (F19/F20) — NOT by the merge-back block, which runs AFTER this
# fence and whose own last step deletes WT on success (issue #494, ADR-0159); B is this batch's
# number. Terminator at COLUMN 0: an indented one is swallowed and destroys this fence's exit code
# silently.
export WT B CLAUDE_PLUGIN_ROOT
bash <<'FENCE_BASH'
set -u
# Two-tier helper resolution, deliberately identical to autopilot-build checks 6 and 7 rather than
# extracted: a fence that borrowed a path bound in another fence would stop being independently
# executable, which is the property ADR-0083 F4/F7 rest on.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/scripts/dispatch-state.sh" ]; then
  _ds="$CLAUDE_PLUGIN_ROOT/scripts/dispatch-state.sh"
elif [ -f "$HOME/.claude/hooks/dispatch-state.sh" ]; then
  _ds="$HOME/.claude/hooks/dispatch-state.sh"
else
  echo "HALT: dispatch-state.sh not found — the check DID NOT RUN. Run: bash <repo>/staging/sync-to-claude.sh --apply"
  exit 2
fi
[ -n "${WT:-}" ] || { echo "HALT: WT is unset — bind it from the dispatch result before this fence runs"; exit 2; }
[ -n "${B:-}" ]  || { echo "HALT: B is unset — bind this batch's number"; exit 2; }
ST=$(bash "$_ds" "$WT" "step5-batch-$B" 2>&1); RC=$?
[ "$RC" -eq 3 ] && { echo "HALT: dispatch-state DID NOT RUN for batch $B — $ST"; exit 2; }
[ "$RC" -eq 2 ] && { echo "HALT: dispatch-state bad invocation for batch $B — $ST"; exit 2; }
case "${ST%%|*}" in
  DONE)    echo "batch $B complete: ${ST#*|}" ;;
  PENDING) echo "HALT: batch $B dispatched and not finished — do NOT advance or transition"; exit 2 ;;
  NONE)    echo "HALT: batch $B has no completion fact — the coder never wrote one"; exit 2 ;;
  PARTIAL) echo "HALT: batch $B completion fact is half-written — verify by hand"; exit 2 ;;
  UNREADABLE) echo "HALT: batch $B completion fact is unreadable — verify by hand"; exit 2 ;;
  *)       echo "HALT: unrecognised token ${ST%%|*} for batch $B"; exit 2 ;;
esac
FENCE_BASH
```

On any `HALT` line: do NOT run the merge-back, do NOT continue to the next batch or transition —
the worktree named by `$WT` still holds it, untouched. Present the line to the user and wait for
acknowledgment. On the `complete` line: run the **Merge-back and base-fork audit** block above
against this coder's worktree, THEN proceed with controller-side verification as normal.

**Which half is enforcement (rule 16).** The helper's answer is a fact about the filesystem and the
fence exits non-zero on every non-`DONE` token — that half is mechanical. That the orchestrator then
stops rather than pressing on is an instruction, exactly as it was before. What changed is that the
check no longer consults a channel that cannot carry the answer.

After all batches complete and controller-side verification passes, transition to
`step_6_review`. Present Gate 5.

Set `step5_mode: "agent_batch"` in the manifest when the fallback activates (via bash sed substitution on the additive field — NOT via Edit tool, NOT via manifest-set-flag.sh which is boolean-only). <!-- path-rule-exempt: negated -- says NOT to use this helper for the step5_mode write, describing what not to do -->

