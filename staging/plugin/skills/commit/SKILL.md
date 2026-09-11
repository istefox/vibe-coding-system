---
name: commit
description: Use this skill for ANY git commit request — including "commit", "commit and push", "create PR", "commit then PR", "merge this". Generates a Conventional Commits message with explicit HITL approval gate before executing. Auto-creates a feature branch when needed (never commits to the default branch). Optionally pushes and creates a PR, always checks CI once a PR is open, and proposes (never auto-executes) the merge once CI is green. Reads context (diff, CLAUDE.md, ADR/manifest). NEVER commits or merges before the explicit user click. Supersedes commit-commands:commit and commit-commands:commit-push-pr.
---

# `commit` — Commit Wizard Skill

Closes the implementation cycle with a HITL-verified Conventional Commit.
**NEVER run `git commit` before the explicit "Approve" click.**

## When to invoke

- After implementation + review: code is ready, only the commit is missing.
- As Step 7 in the `concept-to-code` chain (after Gate 5 / review cycle).
- Standalone on any branch with changes to commit.

**Do NOT invoke if:**
- No git repo (`git rev-parse --git-dir` fails).
- `git status --short` is empty (nothing to commit).

## Arguments

```
/commit [context-hint] [--autopilot] [--no-pr] [--branch <name>] [--include <path>[,<path>...]]
```

Optional `context-hint`: brief feature description for the commit body.
From the concept-to-code chain: `<topic-full-title> (ADR: <adr-path>)`.

`--autopilot`: when present in args, **skip Step 4 HITL gate** and execute the commit immediately with the generated message. Emit: `"Commit: autopilot — executing commit directly..."` before `git commit`. Step 6 (PR) is also skipped in autopilot mode. **Only set by project-conductor or c2c when `manifest.autopilot=true`** — never set manually unless you explicitly want unattended commits.

`--no-pr`: **skip Step 6 and everything downstream of it** (6, 6b, 6c, 7) — no PR question, no push, no CI watch, no merge proposal. The Step 4 HITL gate is **unaffected**: this flag suppresses publication, never approval, and it is the difference between it and `--autopilot`. The two are orthogonal and may be combined.

`--branch <name>`: **ensure the commit lands on `<name>`, creating it from the current HEAD if it does not exist** (issue #363, ADR-0127 §D3). Orthogonal to `--autopilot` and `--no-pr` exactly as those two are to each other; combinable with all of them.

Without it, Step 3.6 derives a branch name from the commit **subject**, and that derivation is what #363 is about: on the unattended path Gate 4.0's commit is a planning-artifacts commit, so its type is `docs`, so the derived name is `chore/<subject-slug>` — while `publish-feature.sh` pushes `feat/<topic-slug>`. **The two never coincide**, and the 2026-08-04 run published only because a human created the branch by hand first.

Four rules:

1. **It ensures, it does not merely name.** Already on `<name>` → no-op. On any other branch, including the default branch, a detached HEAD, or a run-scoped base like `autopilot/prep-<date>` → check `<name>` out, creating it from the current HEAD when absent. The "any other branch" half is load-bearing: under ADR-0127 §D4 each feature forks from the prep branch, which is *not* the default branch, so a trigger conditioned only on "am I on the default branch" would no-op and commit the feature onto the shared base.
2. **An existing `<name>` is REUSED, never suffixed.** The derived path appends `-2`, `-3` … on collision, which is right for an accidental slug clash and wrong here: `publish-feature.sh` expects exactly `feat/<slug>`, so a suffixed branch is one nothing will ever push. A pre-existing `<name>` is a resumed feature, not a collision.
3. **`<name>` must not be the default branch.** Refuse and stop — the invariant this step exists to enforce is not negotiable by an argument.
4. **Absent, behaviour is byte-identical to today.** The derivation, the collision suffix and the no-op case are untouched for every caller that does not pass it (#363 R-03).

`--include <path>[,<path>...]`: **add these exact paths to the included set, untracked ones too** (issue #234, ADR-0071 §D2's Clarification). Comma-separated, repo-relative or absolute; a path containing a comma cannot be expressed and that limit is deliberate rather than worked around.

This exists because the default rule — *untracked files are never staged, under any circumstance* — is right for a human at Step 4 and leaves an unattended caller with no door at all: `--autopilot` skips Step 4, which is where the only explicit-staging path lives. `concept-to-code` Gate 4.0 is the first such caller and could not commit the planning artifacts, which are untracked on a greenfield chain.

Four rules, and they are the whole contract:

1. **It widens the included set; it does not bypass anything.** The paths join the set Step 1 computes, and Step 5 stages them alongside `git add -u`. Every check in Step 1 still sees one coherent set.
2. **It resolves AFTER the secrets check, never before.** The scan already covers `staged ∪ tracked_modified ∪ untracked`, so an `--include` path is in it either way — but the ordering must stay explicit, because a future edit that resolved `--include` first would open the door the filename rule exists to keep shut.
3. **A path that does not exist aborts the commit, naming it.** A caller naming a missing artifact has a defect upstream, and committing the rest silently produces a half-done Gate 4.0 that looks complete. This is the same discipline as "an empty finding list from a run that never happened is not a clean result".
4. **Never `git add .` / `git add -A` to satisfy it.** The paths are added individually, by name.

**Only a caller that knows exactly which paths it wants may pass this.** It is not a convenience for widening a commit; a human who wants more files uses Step 4's "Stage additional files", which shows them first.

Use it when a commit is a checkpoint rather than a deliverable — the caller knows there is nothing to publish yet, so asking would be pure friction on every run. `concept-to-code` Gate 4.0 (ADR-0071) is the first such caller: it commits the planning artifacts so Step 5's recovery pre-flight has the clean, on-a-feature-branch tree it requires, with implementation still to come. After the flag suppresses Step 6, emit `"Commit: --no-pr — PR/push/merge skipped."` so the absence of the usual question is visible rather than looking like a step that silently failed.

---

## Process

### Step 1 — Verify repo and state, compute file scope

```bash
git rev-parse --git-dir
```

If it fails: report "Not in a git repository" and stop.

```bash
git status --short
```

Empty output → report "Nothing to commit" and stop.

**Scope rules — never `git add .` or `git add -A` blindly:**

```bash
staged=$(git diff --name-only --staged)
tracked_modified=$(git diff --name-only HEAD --diff-filter=ACMRD)   # tracked changes only
untracked=$(git ls-files --others --exclude-standard)                # NEVER auto-staged
```

- Nothing staged, `tracked_modified` non-empty → **included set = `tracked_modified`**, staged
  via `git add -u` right before Step 5 (tracked modifications/deletions/renames only — never
  touches `untracked`).
- Something already staged → keep today's behavior: included set = `staged` only; unstaged
  tracked changes are mentioned as "not included", not swept in.
- `untracked` non-empty in either case above → always list separately in the Step 4 gate as
  "Excluded — untracked, not staged". Never staged by default, under any circumstance — adding
  one requires the explicit "Stage additional files" path in Step 4, or `--include` from a caller
  that names the paths (see below).
- **`--include` resolution (issue #234), and it happens HERE, after the secrets check below, not
  before it.** Split the flag's value on commas into `include_paths`; empty when the flag is
  absent, which is exactly today's behaviour for every caller that does not pass it. Each path
  joins the included set and is dropped from the "Excluded — untracked" list, since it is no
  longer excluded.
  <!-- fence-contract: commit-step1-include-resolve -->
  ```bash
  # ADR-0133 §D1 (issue #394): everything between the two FENCE_BASH lines runs under BASH, not
  # under the host shell. `for _inc in $include_paths` needs the word split bash performs on an
  # unquoted expansion; zsh — the host shell here — does not perform it, so the loop saw one blob
  # and checked a path nobody named. `export` forwards this body's caller-bound free variable
  # across the new process boundary. The terminator sits at COLUMN 0 even though this fence is
  # indented inside a list item: an indented terminator is swallowed into the here-document and
  # destroys this fence's exit code silently. It is not a formatting slip — do not tidy it.
  export include_flag
  bash <<'FENCE_BASH'
  # $include_flag is the raw value after --include, or empty.
  include_paths=$(printf '%s' "${include_flag:-}" | tr ',' '\n' | sed '/^[[:space:]]*$/d')
  _missing=""
  for _inc in $include_paths; do
    [ -e "$_inc" ] || _missing="$_missing $_inc"
  done
  # ADR-0133 §D4: the wrapper runs this body in a SUBPROCESS, so `include_paths` and `_missing` die
  # at the terminator below. Step 5's staging fence reads `include_paths`, and the paragraph
  # immediately below reads `_missing`; both used to receive them only because the blocks happened
  # to share a shell — an implicit inter-block dependency nothing documented. Printed now: the
  # orchestrator reads these lines and carries both values, exactly as it carries `<commit-message>`.
  # One path per INCLUDE line, so a path containing a space stays one value. The INCLUDE lines are
  # emitted only when there are paths — an absent `--include` produces none, which is the same
  # silence every caller that does not pass the flag saw before. INCLUDE-MISSING is emitted always,
  # empty tail and all, so "checked, nothing missing" stays distinguishable from "did not run".
  if [ -n "$include_paths" ]; then printf 'INCLUDE: %s\n' $include_paths; fi
  printf 'INCLUDE-MISSING:%s\n' "$_missing"
FENCE_BASH
  ```
  **`_missing` non-empty → stop and report it, do not commit.** A caller naming a path that is not
  there has a defect upstream of this skill, and committing the rest produces a half-done result
  that looks complete — the same reason an unrun check is not a clean result. Name every missing
  path, not the first.
- **This untracked list is the authoritative, mechanical signal for debris (ADR-0062 §D2, issue
  #116).** An agent's own cleanup disposition list (its Output Format "Cleanup" bullet — coder,
  debugger, refactorer) is a self-report by the party being audited — the same class of evidence
  ADR-0047 §A3 refused to trust for `weakening_findings` and ADR-0057 §D3 for the tracer verdict —
  and is never treated as verification here. An agent that forgot to clean something up will also
  forget to list it; git does not forget.
- Included set empty **and** `untracked` non-empty (only brand-new files exist, nothing
  tracked-modified or pre-staged) → this is real work, not "nothing to commit": proceed to
  Step 4 with 0 included files and the no-`Approve` gate variant described there, instead of
  reporting "nothing to commit".
- **Secrets check runs here**, over `staged ∪ tracked_modified ∪ untracked` (not just the
  included set): if any path matches `.env`, `*secret*`, `*credential*`, `*.pem`, stop and warn
  per the Invariant guardrails — even a file that would never be auto-included by default can
  still be requested explicitly in Step 4, so catch it before that door opens.

**Content scan, dependency gate and anti-test-weakening scan (ADR-0046, ADR-0047).** The filename
check above catches a file *named* like a secret. It cannot see a key pasted into `src/config.py`,
it says nothing about a dependency an agent added to get past a hard problem, and it says nothing
about a test quietly deleted or skipped to make a red suite look green. Three reporters cover all
three, over the same union set (`weakening-scan.sh` reuses `git diff HEAD`, the same input already
computed for the dependency gate):

```bash
# Script resolution — plugin install first, ~/.claude deployment second (the order used by
# project-conductor/SKILL.md). If NEITHER resolves, run neither script and apply the filename
# check above exactly as it is written: an un-synced machine keeps today's behaviour precisely.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/scripts/secret-scan.sh" ]; then
  _scripts="$CLAUDE_PLUGIN_ROOT/scripts"
elif [ -f "$HOME/.claude/hooks/secret-scan.sh" ]; then
  _scripts="$HOME/.claude/hooks"
else
  _scripts=""    # neither resolves — filename check only, no content scan, no dependency gate
fi

# weakening-scan.sh lives under review-triage-fix/scripts/, not alongside secret-scan.sh/
# dependency-scan.sh (ADR-0047 §D2) — it is invoked in place, never copied. Same two-tier order.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/skills/review-triage-fix/scripts/weakening-scan.sh" ]; then
  _wscan="$CLAUDE_PLUGIN_ROOT/skills/review-triage-fix/scripts/weakening-scan.sh"
elif [ -f "$HOME/.claude/skills/review-triage-fix/scripts/weakening-scan.sh" ]; then
  _wscan="$HOME/.claude/skills/review-triage-fix/scripts/weakening-scan.sh"
else
  _wscan=""    # neither resolves — no weakening scan; SECRET/NEWDEP checks above still apply
fi

secret_findings=""; dep_findings=""; secret_rc=0; dep_rc=0; weakening_findings=""
if [ -n "$_scripts" ]; then
  scan_list=$(mktemp)
  printf '%s\n%s\n%s\n' "$staged" "$tracked_modified" "$untracked" \
    | sed '/^$/d' | sort -u >"$scan_list"
  secret_findings=$(bash "$_scripts/secret-scan.sh" --files "$scan_list"); secret_rc=$?
  dep_findings=$(git diff HEAD | bash "$_scripts/dependency-scan.sh" --diff); dep_rc=$?
  rm -f "$scan_list"
fi
if [ -n "$_wscan" ]; then
  weakening_findings=$(git diff HEAD | bash "$_wscan")
  # never gate on empty output — the reporter prints CLEAN on no finding, never nothing; gate on
  # printf '%s\n' "$weakening_findings" | grep -q '^WEAKENED', never [ -n "$weakening_findings" ].
fi
```

Reading the result — the scripts report, this step decides:

- **Any `SECRET` line stops Step 1 and warns.** Filename rule and content rule alike; this is the
  existing "NEVER commit `.env`, secrets, API keys" invariant applied deterministically instead of
  by judgement. Only an explicit human instruction resumes the flow, and if it does, every finding
  is rendered verbatim in the Step 4 gate so it is visible at the click.
- **`NEWDEP` lines never stop anything.** They are advisory: render them in the Step 4
  `Pre-commit findings` block and proceed.
- **A CLEAN weakening scan is not evidence that no test was weakened (ADR-0073 §D4, issue #177).**
  An assertion edited in place is invisible to every detector in `weakening-scan.sh` — the counts
  match, so `assert-removed` cannot fire. This is precisely why the **Test diff** section below
  exists and is not optional: it is the only thing in this flow that puts a changed assertion in
  front of a human.
- **`WEAKENED` lines are advisory in attended mode.** They render in the Step 4 `Pre-commit
  findings` block and stop nothing here — `review-triage-fix`'s own circuit breaker B is the actual
  enforcement point; this call is a heads-up at commit time, not a second gate.
- **`SUSPECT` lines (ADR-0051, issue #105) are advisory ALWAYS, including under `--autopilot`.**
  They are the reward-hacking heuristics (`zero-assertion-test`, `deleted-public-symbol`,
  `swallowed-error` — `literal-assertion-added` was retired on measurement, #314 / ADR-0144) emitted by the same
  `weakening-scan.sh` call, extracted with `printf '%s\n' "$weakening_findings" | grep '^SUSPECT'`
  — never `[ -n ... ]`, same trap as `WEAKENED`. Render them in the Step 4 `Pre-commit findings`
  block (attended) or print them alongside the other reporters (autopilot, since Step 4 is
  skipped there). Unlike `SECRET` and `WEAKENED`, a `SUSPECT` finding **never aborts the commit,
  in any mode** — it is a heuristic over a diff with no type information and no test execution
  (ADR-0051 §D2), the same reason it does not gate the Step 5 → Step 6 transition.
- **Exit code 2 or 3 means the check did NOT run** (bad invocation, or an awk that cannot express
  the rules). Report it as unknown and say so — an empty finding list from a run that never
  happened is not a clean result.
- **In `--autopilot` mode** (Step 4 is skipped there, so the gate cannot be what catches this): any
  `SECRET` finding **aborts the commit**, prints the findings, and exits without committing; any
  `WEAKENED` finding **also aborts the commit** the same way, and prints the findings; a `NEWDEP`
  finding is printed and the commit proceeds; a `SUSPECT` finding is printed and the commit
  proceeds — see the bullet above, this is never an abort condition. Aborting unattended on a
  secret or on detected test weakening is the correct fail direction, consistent with
  `ADR-0020`'s autonomy boundary.

`git diff HEAD` covers tracked changes only, so a brand-new, still-untracked manifest is invisible
to the dependency gate. The secret scan's `--files` union does cover it — the asymmetry is known,
and the Step 4 excluded-files list is where an untracked manifest becomes visible to the human.

**Test diff (H4, issue #115, ADR-0061 §D1/§D4).** The commit gate must put the actual diff inside
test files in front of the human, not one line among many in the file list and not a model's
summary of it — a green suite means the implementation satisfies the tests, so a test the human
never read is an accept decision the human never made.

Reuses `weakening-scan.sh`'s own `is_test()` regex (`review-triage-fix/scripts/weakening-scan.sh`),
not `spec-coverage.sh`'s narrower basename-only predicate (ADR-0048 §D3). The two diverge on
purpose — ADR-0048 §D3 draws the line as a DISCOVERY predicate must not over-match, a DENIAL
predicate must not under-match — and this is neither: it decides what to **show** a human. The
dangerous failure here is under-match: a missed test file's diff never reaches this gate at all,
which produces the exact silent-omission failure §D1 forbids by accident rather than by the
legitimate "no test files changed" case. The broader predicate's only cost is an occasional false
positive — a stray non-test file shown under the "Test diff" heading, still visible, never hidden.
That is why the broader predicate wins here even though it is the one ADR-0048 flagged as
over-matching `.spec.md` files for spec-coverage.sh's different (discovery) purpose.

<!-- fence-contract: commit-h4-test-diff-classify -->
```bash
# ADR-0133 §D1 (issue #394): everything between the two FENCE_BASH lines runs under BASH, not
# under the host shell. This is the fence whose wrong behaviour was OBSERVED live on 2026-08-08
# and misattributed to an orchestrator scripting error: `for _f in $staged $tracked_modified
# $untracked` needs the word split bash performs on an unquoted expansion, and zsh — the host
# shell here — does not perform it, so the loop received ONE blob containing every changed path,
# the classification ERE matched it whenever any path looked like a test, and every changed file
# was shown under "Test diff". Failing closed and wrongly, which reads as a defect elsewhere.
# `export` forwards this body's caller-bound free variables across the new process boundary. The
# terminator sits at COLUMN 0 on purpose: an indented one is swallowed into the here-document and
# destroys this fence's exit code silently. Do not tidy either line.
export staged tracked_modified untracked
bash <<'FENCE_BASH'
# The classification ERE below replicates weakening-scan.sh's is_test() exactly (see prose above
# for why the broader, over-matching predicate — not spec-coverage.sh's narrower one — is the
# correct choice for a section that SHOWS a diff to a human rather than gating on it).
# It is INLINED at its single call site — no helper, no scripts/ file, no PAIRS entry, no ~/.claude
# dependency (ADR-0132 §D3, issue #385): an external helper would be paid for by concept-to-code
# Step 7, project-init and autopilot-build, and its unresolved-helper fallback could only be "no
# test files found", which is the silent omission this gate exists to prevent.
test_files=""
for _f in $staged $tracked_modified $untracked; do
  [ -n "$_f" ] || continue
  printf '%s\n' "$_f" | grep -qE '(^|/)tests?/|(^|/)spec/|test_[^/]*\.[A-Za-z]+$|_test\.[A-Za-z]+$|\.test\.[A-Za-z]+$|\.spec\.[A-Za-z]+$|Tests?\.[A-Za-z]+$' && test_files="$test_files
$_f"
done
test_files=$(printf '%s\n' "$test_files" | sed '/^$/d' | sort -u)

# The diff itself, tracked and untracked test files alike — a brand-new, still-untracked test
# file must not be silently excluded from the one gate that exists to show it (the same
# tracked-only asymmetry noted above for the dependency gate would otherwise repeat here for
# exactly the file H4 cares most about).
test_diff=""
TEST_DIFF_MAX_LINES=400
if [ -n "$test_files" ]; then
  while IFS= read -r _tf; do
    [ -n "$_tf" ] || continue
    if git ls-files --error-unmatch -- "$_tf" >/dev/null 2>&1; then
      _one_diff=$(git diff HEAD -- "$_tf")
    else
      _one_diff=$(git diff --no-index -- /dev/null "$_tf" 2>/dev/null)
    fi
    [ -n "${_one_diff:-}" ] && test_diff="$test_diff
$_one_diff"
  done <<TESTFILES_EOF
$test_files
TESTFILES_EOF
fi
test_diff=$(printf '%s\n' "$test_diff" | sed '/^$/d')

# Truncation is labelled, never silent (ADR-0061 §D4) — a truncated diff still looks complete
# unless the label and the command to see the rest are both printed.
test_diff_truncated=0
test_diff_total_lines=0
if [ -n "$test_diff" ]; then
  test_diff_total_lines=$(printf '%s\n' "$test_diff" | wc -l | tr -d ' ')
  if [ "$test_diff_total_lines" -gt "$TEST_DIFF_MAX_LINES" ]; then
    test_diff_truncated=1
    test_diff=$(printf '%s\n' "$test_diff" | head -n "$TEST_DIFF_MAX_LINES")
  fi
fi
FENCE_BASH
```

- **`test_files` empty → the entire "Test diff" section is omitted from Step 4**, not rendered
  empty. A section that usually says "none" trains the eye to skip it, and this is the one section
  that must not be skipped (ADR-0061 §D1, alternative A5 rejected).
- **`test_diff` is rendered verbatim in Step 4** — the real diff content, never a model-written
  description of it (ADR-0061 §D4; the same objection ADR-0057 §D3 made to a self-assessed tracer
  verdict, and ADR-0047 §D-trust made to trusting an agent's own `weakening_findings`).
- **`test_diff_truncated=1` → the section carries the label and the exact command to see the
  rest**: `git diff HEAD -- <test_files, space-joined>`. Silent truncation is worse than no gate,
  because it looks like the whole thing (ADR-0061 §D4).

### Step 2 — Read context

In priority order:
1. `git diff --staged` (or `git diff HEAD` if nothing staged) — what changes
2. `CLAUDE.md` project root — stack, patterns, conventions
3. Most recent manifest in `docs/manifests/` if present — topic, ADR path
4. Most recent ADR in `docs/architecture/` if present — cycle decisions
5. `context-hint` passed as argument

### Step 3 — Generate commit message

Conventional Commits format (English):
```
<type>(<scope>): <subject>

<body>
```

- **type**: `feat` | `fix` | `refactor` | `test` | `docs` | `chore` | `perf`
- **scope**: main module/component touched (optional but recommended)
- **subject**: imperative, lowercase, no trailing period, subject + type + scope ≤ 72 chars
- **body**: only if it adds a non-obvious "why" beyond the diff (max 5 lines)
- **NEVER** add `Co-Authored-By: Claude` or similar trailers (`settings.json attribution` already disabled)
- **NEVER** add `BREAKING CHANGE` unless explicitly verified from the diff

> **Step 3.5 (humanize message) was removed** — see ADR-0040. A commit message is an internal
> artifact, so it never gets a humanize pass. Step numbering is unchanged on purpose: other
> skills refer to these steps by number.

### Step 3.6 — Ensure feature branch (automatic, no gate)

Runs unconditionally, including in `--autopilot` mode (there is no gate here to skip). Enforces
the project invariant "always on a feature branch, never commit directly to the default branch".

**Default-branch detection — compute once, reuse this exact block in Step 6/6b/7 too, never
re-hardcode `"main"` anywhere in this file:**

```bash
default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
if [ -z "$default_branch" ]; then
  git remote set-head origin -a >/dev/null 2>&1 || true
  default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
fi
if [ -z "$default_branch" ] && command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  default_branch=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null)
fi
[ -z "$default_branch" ] && git show-ref --verify --quiet refs/heads/main && default_branch="main"
[ -z "$default_branch" ] && git show-ref --verify --quiet refs/heads/master && default_branch="master"
[ -z "$default_branch" ] && default_branch="main"   # brand-new repo, no remote/local ref yet
```

**Trigger, two paths.** With `--branch <name>` (`$branch_flag`): runs whenever the current branch
is not already `<name>`. Without it, the original trigger — current branch
(`git branch --show-current`, empty string means detached HEAD) equals `$default_branch`, or is
empty.

<!-- fence-contract: commit-ensure-feature-branch -->
```bash
# ADR-0133 §D1 (issue #394): everything between the two FENCE_BASH lines runs under BASH, not under
# the host shell, which is zsh here and differs from bash on word splitting, unmatched globs and
# `echo` escapes — so a fence written for bash is not the program that runs. `export` forwards this
# body's caller-bound free variables across the new process boundary; a plain shell variable does
# not survive it. `branch_name` is unaffected by that boundary: every path that changes the branch
# already ECHOES it, and the rest of this file receives it as the `<branch_name>` placeholder the
# orchestrator carries. The terminator sits at COLUMN 0 on purpose: an indented one is swallowed
# into the here-document and destroys this fence's exit code silently — which on this fence would
# mean a failed branch creation reporting success, and a commit landing on the default branch.
export branch_flag default_branch subject type
bash <<'FENCE_BASH'
current_branch=$(git branch --show-current)

# --branch <name> (issue #363): ensure, do not merely name. Handled before the derived path
# because its trigger is different — "not already on <name>" rather than "on the default branch".
# A trigger conditioned on the default branch alone would no-op on a run-scoped base such as
# autopilot/prep-<date> (ADR-0127 §D4) and commit the feature onto the shared base.
if [ -n "${branch_flag:-}" ]; then
  if [ "$branch_flag" = "$default_branch" ]; then
    echo "Error: --branch names the default branch ('$default_branch'). Refusing."
    exit 1
  fi
  if [ "$current_branch" = "$branch_flag" ]; then
    branch_name="$current_branch"          # already there — no-op
    echo "Branch: already on '$branch_name' (--branch), nothing to do."
  elif git show-ref --verify --quiet "refs/heads/$branch_flag"; then
    # REUSE, never suffix: publish-feature.sh expects exactly this name, so a `-2` variant is a
    # branch nothing will ever push. A pre-existing branch here is a resumed feature.
    git checkout "$branch_flag" || { echo "Error: could not switch to existing '$branch_flag'."; exit 1; }
    branch_name="$branch_flag"
    echo "Branch: switched to existing '$branch_name' (--branch; reused, not suffixed)."
  else
    git checkout -b "$branch_flag" || { echo "Error: could not create '$branch_flag'."; exit 1; }
    branch_name="$branch_flag"
    echo "Branch: created '$branch_name' from '${current_branch:-detached HEAD}' (--branch)."
  fi
elif [ "$current_branch" = "$default_branch" ] || [ -z "$current_branch" ]; then
  # prefix from Step 3's <type> — only feat/fix are literal, everything else
  # (refactor/docs/test/chore/perf, or a genuinely mixed change) is the chore catch-all
  case "$type" in
    feat) prefix="feat" ;;
    fix)  prefix="fix" ;;
    *)    prefix="chore" ;;
  esac

  # slug: lowercase, kebab, max 40 chars — same rule and regex as concept-to-code's
  # topic-slug (concept-to-code/scripts/manifest-init.sh: ^[a-z0-9-]{1,40}$)
  slug=$(printf '%s' "$subject" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-40 | sed -E 's/-+$//')
  [ -z "$slug" ] && slug="wip"
  case "$slug" in main|master|head|trunk) slug="${slug}-changes" ;; esac

  branch_name="${prefix}/${slug}"

  # collision handling (e.g. a second, unrelated "update readme" commit from
  # $default_branch in a later session, same slug): suffix, don't silently overwrite
  n=2; base="$branch_name"
  while git show-ref --verify --quiet "refs/heads/$branch_name" \
     || git ls-remote --exit-code --heads origin "$branch_name" >/dev/null 2>&1; do
    branch_name="${base}-${n}"; n=$((n + 1))
    [ "$n" -gt 20 ] && branch_name="${base}-$(date +%H%M%S)" && break
  done
  [ "$branch_name" != "$base" ] && echo "Branch '$base' already exists — using '$branch_name' instead."

  git checkout -b "$branch_name" || {
    echo "Error: could not create branch '$branch_name'. Stopping — refusing to commit to '$default_branch'."
    exit 1
  }
  echo "Branch: created and switched to '$branch_name' (was on '${current_branch:-detached HEAD}')."
else
  branch_name="$current_branch"   # already on a feature branch — reuse it, no-op
fi
FENCE_BASH
```

If branch creation fails: **STOP** — never fall through to Step 4/5 while still on
`$default_branch`. This step is what actually enforces "never commit to the default branch" for
every caller of this skill, including `concept-to-code`'s Step 7 (which itself never creates a
persistent branch before invoking `commit`).

**Stacked-PR CI gap (VCS-029).** When the "already on a feature branch — reuse it" no-op path
above fires — i.e. `$current_branch` at invocation was itself a feature branch, not
`$default_branch` — the PR Step 6 later opens will have that feature branch as its base, not
`$default_branch`. Re-verified 2026-09-11 against the consolidated `.github/workflows/
docs-ci.yml`: its trigger is still `on: pull_request: branches: [main]`, which filters on the
PR's *base* branch, so **a PR whose base isn't `main` runs zero CI checks** — `gh pr checks`
reports "no checks reported", not a failure. Nothing in `gh pr merge` or Step 7 catches this; a
zero-check PR is mergeable into its base with no verification at all. If this is a stacked PR,
merge it into its base first so every commit passes through one real CI gate on a `main`-based
PR, rather than merging the stack straight through unverified.

### Step 3.7 — Recommend CI tier (blocking gate, attended; auto-applies under `--autopilot`)

VCS-051 / ADR-0180. **Design note:** Step 3 (above) drafts the commit message BEFORE this step
runs, so the `CI: <tier>` trailer decided here is appended to that already-drafted message in
place, right before Step 4 renders it — the simplest option, and the least invasive to Step 3's
own text (the alternative, moving trailer insertion to Step 5, was rejected: Step 4 is the last
point before `git commit`, and the human must see the trailer they are approving, not a message
that gains one silently after approval).

**Why this exists:** a pure-documentation PR still ran the full plant registry (4 shards,
10-15 min each) plus every harness loop, because nothing distinguished a prose-only change from
one touching code the registry actually verifies. The tier is derived from the plant registry
itself, not a hand-written path rule — 11 of the registry's 100 declared targets live under
`docs/`, so "docs/ is prose, skip the heavy jobs" would silently skip the registry's own
verification targets.

<!-- fence-contract: commit-step37-ci-tier-classify -->
```bash
# ADR-0180 (VCS-051): everything between the two FENCE_BASH lines runs under BASH, not under the
# host shell (zsh here), which does not word-split the same way a loop over $staged/$tracked_modified
# /$untracked would need. This fence recomputes the changed-file union itself rather than reusing
# Step 1's — the two run as separate tool invocations and shell state does not carry between them —
# so there is no caller-bound variable to `export`; the fence is self-contained and independently
# testable. The terminator sits at COLUMN 0 on purpose: an indented one is swallowed into the
# here-document and destroys this fence's exit code silently.
bash <<'FENCE_BASH'
staged=$(git diff --name-only --staged)
tracked_modified=$(git diff --name-only HEAD --diff-filter=ACMRD)
untracked=$(git ls-files --others --exclude-standard)
changed_file=$(mktemp)
printf '%s\n%s\n%s\n' "$staged" "$tracked_modified" "$untracked" | sed '/^$/d' | sort -u >"$changed_file"

# Prefer this repo's own dev copy (pre-sync); fall back to the deployed hook everywhere else.
# CI_TIER_SH lets a test point this fence at a fixture binary without touching the resolution order.
CI_TIER_SH="${CI_TIER_SH:-staging/plugin/scripts/ci-tier.sh}"
[ -f "$CI_TIER_SH" ] || CI_TIER_SH="$HOME/.claude/hooks/ci-tier.sh"

classify_out=$(bash "$CI_TIER_SH" --classify "$changed_file" 2>"$changed_file.err")
classify_rc=$?

if [ "$classify_rc" -eq 3 ]; then
  # DID-NOT-RUN is not a clean result (rule 4) — never silently downgrade to docs/standard.
  computed_tier="full"
  reason=$(grep 'DID-NOT-RUN' "$changed_file.err" | head -1)
  echo "computed_tier=full"
  echo "did_not_run=${reason:-ci-tier.sh exited 3 with no DID-NOT-RUN line}"
else
  computed_tier=$(printf '%s\n' "$classify_out" | grep '^TIER: ' | head -1 | sed 's/^TIER: //')
  [ -n "$computed_tier" ] || computed_tier="full"
  echo "computed_tier=$computed_tier"
fi
printf '%s\n' "$classify_out" | grep '^PLANT-MATCH: ' | sed 's/^PLANT-MATCH: /plant_match=/'
rm -f "$changed_file" "$changed_file.err"
FENCE_BASH
```

Read `computed_tier` and any `plant_match=` lines from the fence's output.

**`--autopilot` in args:** skip the `AskUserQuestion` below entirely. Auto-apply `computed_tier`
and print exactly one line: `"CI tier: <computed_tier> (autopilot — auto-applied)"`. Set
`ci_tier=<computed_tier>` and continue.

**Otherwise**, use `AskUserQuestion` — three options, one per tier, `computed_tier` listed FIRST
with `" (Recommended)"` appended to its label:

```
question: "CI tier — which checks should this commit's CI run?\n\n
  Computed from the plant registry: <computed_tier>\n
  [Files that matched a plant-registry target:\n<plant_match lines, one per line> — OMIT this
  block entirely when there are no plant_match lines]\n
  [ci-tier.sh could not classify this change (<did_not_run reason>) — defaulting to full —
  OMIT unless classify_rc was 3]\n\n
  Choose the tier for the `CI: <tier>` commit trailer."
header: "CI tier"
options:
  - label: "<computed_tier> (Recommended)"
    description: "<full: 'Everything — plant-shard (4 shards) + shell-tests + ci. Required: a
      changed file matches a declared plant-registry target.' | standard: 'Skips plant-shard only
      — shell-tests and ci still run in full. For staging/**, .github/**, .claude/** changes with
      no plant-target match.' | docs: 'Skips plant-shard AND the harness loops in shell-tests/ci
      — markdownlint and links still run. For prose-only changes outside staging/**, .github/**,
      .claude/**.'>"
  - label: "<the other two tiers, in strictness order, each with its own description above>"
  - label: "<...>"
```

Store the selected label as `ci_tier`. **Append the trailer to the commit message Step 3 already
drafted**: if the body is non-empty, one blank line then `CI: <ci_tier>`; if the body is empty,
one blank line after the subject then `CI: <ci_tier>`. The message shown at Step 4 (and executed
in Step 5) is this trailer-carrying version, never the pre-Step-3.7 draft.

### Step 4 — HITL gate (AskUserQuestion, BLOCKING — human approval required)

Use `AskUserQuestion`. This decision requires explicit human approval — do NOT auto-answer or auto-complete this gate.

**Normal variant (included-file count > 0):**

```
question: "Commit — Human approval required\n\n
  Branch: <branch_name>\n\n
  Proposed message:\n\n```\n<commit-message>\n```\n\n
  Files included (<N>):\n<file-list max 10 lines, then '... and N more'>\n\n
  Excluded — untracked, not staged (<M>):\n<file-list max 10 lines, then '... and M more'>
  \n(say which to add, if any, via 'Stage additional files')\n\n
  Pre-commit findings (<K>):\n<the SECRET, NEWDEP and WEAKENED lines from Step 1, verbatim,
  max 10 lines then '... and K more' — omit this block entirely when K is 0>\n\n
  [Test diff (<count of test_files>):\n<test_diff, VERBATIM — never a summary>\n<if
  test_diff_truncated=1: 'truncated to <TEST_DIFF_MAX_LINES> of <test_diff_total_lines> lines —
  see the rest: git diff HEAD -- <test_files, space-joined>'>\n\n — entire bracketed block OMITTED
  when test_files is empty, never rendered empty]\n\n
  Approve to execute the commit. Only you can authorize this."
header: "Commit · Approval"
options:
  - label: "Approve — execute commit"
    description: "Runs git commit with this message and only the files listed as included"
  - label: "Edit message"
    description: "Select Other and type the corrected message"
  - label: "Stage additional files"
    description: "Select Other and list paths (from the excluded list or elsewhere) to add"
  - label: "Abort"
    description: "Do not commit anything — exit without changes"
```

> **`Pre-commit findings` is a named, extensible list, not a two-item block.** It renders whatever
> Step 1's reporters emitted, one line each, unmodified. Issue #101 (ADR-0047) appended `WEAKENED`
> lines from `weakening-scan.sh` to this same block and its call beside the other two in Step 1 —
> no restructuring, no new gate. A `SECRET` line only ever appears here when a human has already
> been warned in Step 1 and explicitly said to continue; rendering it again at the click is
> the point.

> **`Test diff` is its own labelled section, distinct from `Pre-commit findings` and from the
> `Files included` list above it** (ADR-0061 §D1 — H4, issue #115). A test file appearing only as
> one line in `Files included` is the gap H4 closes; folding it into `Pre-commit findings` would
> recreate the same gap one level down. **Omitted entirely, not rendered empty, when `test_files`
> is empty** — see the Step 1 computation above for why an empty section is worse than no section.
> The content is `test_diff` verbatim — the real diff, never a summary — with the truncation label
> and command when `test_diff_truncated=1`.

**Empty-scope variant (included-file count == 0 — only untracked files exist, nothing
tracked-modified or pre-staged):** drop "Approve — execute commit" entirely (never offer an
empty commit — see Invariant guardrails); show only "Stage additional files" and "Abort".

**NEVER run `git commit` before the explicit "Approve — execute commit" click.**
**NEVER auto-answer or auto-complete the AskUserQuestion.**

**After "Stage additional files" with paths provided via `Other`:**
1. For each path: verify it actually appears in `staged ∪ tracked_modified ∪ untracked`; if not,
   warn "not a modified/untracked path: `<path>`" and re-show the gate unchanged.
2. Re-run the Step 1 secrets check specifically on the newly-requested paths before staging —
   this is the only path by which an excluded file can enter the commit.
3. `git add -- <paths>`.
4. Recompute the included/excluded lists and re-render Step 4 from scratch (same structure).

### Step 5 — Execute commit (ONLY after "Approve" click)

<!-- fence-contract: commit-step5-include-stage -->
```bash
# ADR-0133 §D1 (issue #394): everything between the two FENCE_BASH lines runs under BASH, not
# under the host shell. `for _inc in $include_paths` needs the word split bash performs on an
# unquoted expansion; zsh — the host shell here — does not perform it, so a multi-path --include
# reached `git add --` as one blob and staged nothing. `export` forwards this body's caller-bound
# free variables across the new process boundary. The terminator sits at COLUMN 0 on purpose: an
# indented one is swallowed into the here-document and destroys this fence's exit code silently,
# which on this fence means a failed `git commit` reporting success. Do not tidy either line.
export staged tracked_modified include_paths
bash <<'FENCE_BASH'
# Stage the default scope computed in Step 1 (skip if something was already staged
# manually, or if "Stage additional files" in Step 4 already staged what was needed):
if [ -z "$staged" ]; then
  git add -u   # tracked modifications/deletions/renames ONLY — never untracked
fi
# --include paths (issue #234): staged individually, by name, AFTER git add -u and after Step 1's
# secrets check has already seen them in its union. Never `git add .` / `git add -A`. `--` guards a
# path that starts with a dash. Absent flag -> $include_paths is empty and this loop does nothing,
# which is byte-for-byte today's behaviour for the three callers that do not pass it.
for _inc in $include_paths; do
  [ -n "$_inc" ] || continue
  git add -- "$_inc"
done
# VCS-011 (2026-08-05): another session working in this same checkout modified a tracked file
# between Step 1's scope computation and this staging call, and `git add -u` above swept it in
# silently — it stages every tracked modification live in the tree, not only the ones Step 1 saw
# and the human approved at the Step 4 gate. Re-verify the ACTUALLY staged set against Step 1's
# approved scope right now, never trusting the earlier snapshot once staging has run: this is the
# only point in the flow positioned after `git add -u` and before the irreversible `git commit`.
_expected=$(printf '%s\n%s\n' "${staged:-$tracked_modified}" "$include_paths" | sed '/^$/d' | sort -u)
_actual=$(git diff --name-only --staged | sort -u)
if [ "$_actual" != "$_expected" ]; then
  _extra=$(comm -13 <(printf '%s\n' "$_expected") <(printf '%s\n' "$_actual") | tr '\n' ' ')
  echo "Error: staged set does not match Step 1's approved scope — unexpected file(s) swept in by 'git add -u': $_extra. Refusing to commit; re-run Step 1 to re-approve the current scope." >&2
  exit 1
fi
# Commit with approved message:
git commit -m "$(cat <<'COMMITMSG'
<commit-message>
COMMITMSG
)"
FENCE_BASH
```

> **`git check-ignore` exit-code contract:** if you run `git check-ignore -v <files>` to verify
> files before staging, exit code 1 means "none of the listed files are gitignored" — this is a
> clean result, not a failure. Only exit code 128 signals a real error. Always append `|| true`
> when running it in a compound command:
> ```bash
> git check-ignore -v <files> || true
> ```

Verify exit code:
- 0 → report success: hash + subject (`git log -1 --oneline`)
- non-0 → report error, do not retry automatically

After "Edit message" with text provided by the user via Other:
1. Update the message with the provided text.
2. Re-show the commit gate with the new message (same `AskUserQuestion` structure).
3. Only after the second "Approve" execute `git commit`.

After "Abort": exit without doing anything.

### Step 5.5 — Write project context (automatic, no gate)

Immediately after exit 0 on Step 5. Skip in autopilot mode.

Invoke the `session-state` skill in `after commit` mode (ADR-0197) — it owns the
`.claude/context.md` template and the read-before-write handling. Wrap the whole step in
`|| true` — never abort the commit flow if this fails.

### Step 6 — PR (optional, only after successful commit)

**Skipped entirely when `--no-pr` is present in args**, along with Steps 6b, 6c and 7 — this is the
only entry point to all four. Emit `"Commit: --no-pr — PR/push/merge skipped."` and stop after
Step 5.5. Do not run the idempotency check below: an existing open PR is not a reason to override
a caller that said not to publish. `--autopilot` skips this step too, for its own reason; either
flag alone is sufficient and the two may be combined.

**Idempotency check, before the gate:** don't ask again if a PR is already open for this branch
(e.g. a prior invocation of this skill already created one for the same feature branch):

```bash
existing_pr=$(gh pr list --head "$branch_name" --state open --json number,url -q '.[0]' 2>/dev/null)
```

- Non-empty → `pr_number`/`pr_url` = existing values. Report: "PR already open: `<pr_url>` —
  reusing it." Skip straight to Step 6b (CI check) — do not ask the create-PR question again.
- Empty → proceed with the `AskUserQuestion` flow below as normal.

Use `AskUserQuestion`. This is an optional step — only proceed with push/PR after an explicit click.

```
question: "Create a Pull Request? (requires explicit approval)\n\nBranch: <branch_name> → <default_branch>"
header: "PR · Optional"
options:
  - label: "Yes — push + create PR"
    description: "git push origin <branch_name>, then PR via GitHub MCP"
  - label: "No — local commit only"
    description: "Done"
```

If "Yes":
1. `git push -u origin "$branch_name"` (push only after explicit click)
2. Check if `$default_branch` (resolved in Step 3.6 — recompute here with the same block if this
   commit was already on a feature branch at invocation and Step 3.6 didn't run) exists on the
   remote — **required before opening a PR**:
   ```bash
   git ls-remote --exit-code origin "refs/heads/$default_branch" >/dev/null 2>&1 && echo "BASE_EXISTS" || echo "NO_BASE"
   ```
3. If `BASE_EXISTS`: proceed with `mcp__github__create_pull_request`:
   - `title`: subject of the commit message
   - `body`: body of the commit message + ADR reference if present in context. **If this PR closes
     more than one GitHub issue, give each its own `Closes #N` line, own paragraph, never
     `and`/comma-joined on one line** (`closes #489 and #479` closes only #489 — GitHub honours one
     closing keyword per line, VCS-028, ADR-0194 §"PR body" already decided this shape for the
     batched-PR case this codifies for every PR).
   - `base`: `$default_branch`, `head`: `$branch_name`
   - Set `pr_number`/`pr_url` from the response. Proceed to Step 6b.
4. If `NO_BASE` (new/first push — `$default_branch` not yet on remote):
   - **Do NOT attempt `mcp__github__create_pull_request` or `gh pr create`** — it will fail.
   - Report: "Push succeeded to `<branch_name>`. Remote has no `<default_branch>` branch — PR skipped. This is typical for a brand-new repo. To establish it and enable PRs, run: `git push origin <branch_name>:<default_branch>`; then set it as the default branch on GitHub." **STOP** — Steps 6b/6c/7 need an open PR and do not run.

If "No" was chosen, or no PR resulted from the branch above: **stop here** — Steps 6b/6c/7 all
require an open PR and do not run.

### Step 6b — CI check (mandatory whenever an open PR exists)

Runs every time Step 6 (or its idempotency check) produced an open PR. **Never runs in
`--autopilot` mode** — Step 6, its only entry point, is already skipped there; this line is
defense-in-depth, matching this file's existing style of restating invariants that are also
structurally unreachable (e.g. the `--force` push guardrail below).

**Graceful skip, same fail-safe cascade as `clean-public-repo`'s `detect-public-remote.sh`:**
- `command -v gh` fails → skip 6b/6c/7: "gh CLI not found — verify CI manually: `<pr_url>`."
- `gh auth status` fails → skip 6b/6c/7: "gh not authenticated — verify CI manually: `<pr_url>`."
- Remote host is not `github.com` → skip 6b/6c/7: "Non-GitHub remote — CI check unavailable."

**Bounded wait — up to 3 rounds of ~8 minutes, never an unbounded loop:**

```bash
timeout 480 gh pr checks "$pr_number" --watch --fail-fast
rc=$?
```

- `rc=0` → "CI green — all required checks passed." Proceed to Step 7.
- `rc=124` (shell `timeout` fired) or `rc=8` (`gh`'s own "checks pending" code) → still pending.
  Use `AskUserQuestion` (an operational choice, not an approval gate):
  ```
  question: "CI still pending after 8 min on PR #<n> (<pr_url>). What next?"
  header: "CI · Pending"
  options:
    - label: "Keep waiting (8 more min)"
      description: "Round <k+1> of 3 max"
    - label: "Check back later"
      description: "Stop here — re-invoke /commit or check manually: gh pr checks <pr_url>"
    - label: "Investigate now anyway"
      description: "Go to diagnostics with whatever partial state exists"
  ```
  - "Keep waiting" → repeat the bounded wait, up to 3 rounds total, then behave as "Check back
    later" regardless of further choice — never loop unbounded.
  - "Check back later" → report the PR URL, stop cleanly (not an error).
  - "Investigate now anyway" → proceed to Step 6c; any check still `pending` there is reported
    as "not yet resolved", never counted as failed.
- any other nonzero → at least one required check failed → Step 6c.

**Required vs. informational checks — read this repo's own branch protection, never hardcode:**

```bash
required=$(gh api "repos/{owner}/{repo}/branches/$default_branch/protection/required_status_checks" \
  --jq '.contexts // [.checks[].context]' 2>/dev/null)
```

- Call fails (no protection configured, or no permission) → fail-safe: treat every reported
  check as required — never silently ignore a red check because "required" couldn't be
  confirmed.
- Call succeeds → only checks matching `$required` block Step 7; other red checks are still
  reported in Step 6c, labeled "(non-blocking)".

### Step 6c — Diagnose CI failure (mandatory on any red required check; NEVER auto-fix)

```bash
gh pr checks "$pr_number" --json name,state,bucket,link,workflow
```

Filter to `bucket == "fail"`.
- None found (a `--fail-fast` race: one check failed while others were still pending and have
  since resolved) → re-run Step 6b's watch once, briefly; if still nothing failing, treat as
  green and proceed to Step 7.
- Checks still `pending` at this point → report as "not yet finished", never counted as failed.
- Checks `cancelled`/`skipping` → report distinctly ("cancelled/skipped — verify manually"),
  neither green nor a hard fail.

**For EACH failing check (summarize ALL, not just the first):**

```bash
run_id=$(echo "$link" | sed -E 's#.*/runs/([0-9]+)/job/.*#\1#')
gh run view "$run_id" --log-failed
```

Extract the actual root-cause line(s) from the log. If `gh run view --log-failed` itself errors
(log expired/retention, run cancelled rather than failed): fall back to reporting
`bucket`/`state` + the raw `link`, noting "could not fetch log automatically — see: `<link>`".

**Report format (plain text, informational — NOT a gate):**

```
CI red on PR #<n> — <K> check(s) failing:
✗ <check-name> (<workflow>): <one-line root cause>
  Log: <link>
✗ <check-name-2> (<workflow>): <one-line root cause>
  Log: <link>
```

"This skill does not auto-fix failing CI. Address the above, push a fix commit (or re-invoke
`/commit`), and CI will be re-checked next time." **STOP — do not proceed to Step 7.** The
commit/push/PR already happened and are reversible; merge must never be proposed on red CI.

### Step 7 — Merge gate (only reached after Step 6b reports fully green)

**Never automatic — propose only.** A pushed branch and an open PR are reversible; a merge is
not (see `ADR-0022`, `autopilot`'s "merge stays human" invariant — this step doesn't
relitigate that decision, it applies the same principle here).

```bash
repo_settings=$(gh api "repos/{owner}/{repo}" \
  --jq '{squash: .allow_squash_merge, merge: .allow_merge_commit, rebase: .allow_rebase_merge, delete_on_merge: .delete_branch_on_merge}')
```

**Recommended method — read this repo's own settings/history, never hardcode "merge commit":**
1. Only one method allowed by `$repo_settings` → recommend it, done.
2. Otherwise inspect this repo's actual merge history:
   ```bash
   git log --merges --oneline "origin/$default_branch" | head -30
   ```
   - Non-empty, mostly/all "Merge pull request #" → recommend **merge commit**.
   - Empty (linear history) → squash and rebase both produce linear history and aren't
     reliably distinguishable from `git log` alone; approximate via parent count of recently
     merged PRs (`gh pr list --state merged --json mergeCommitSha`, then
     `git cat-file -p <sha> | grep -c '^parent'`): 2 parents → merge commit; 1 parent →
     squash-or-rebase, recommend **squash** as the more common of the two (a documented
     approximation, not a guarantee — say so if used).
3. Zero prior merges (brand-new repo) → fall back to the most information-preserving allowed
   method: merge commit > squash > rebase.
4. Only ever present options actually allowed by `$repo_settings`.

```
question: "CI is green on PR #<n> (<pr_url>). Merge now?\n\nRecommended: <method> — <one-line rationale, e.g. 'this repo's last N merges were all merge commits'>"
header: "Merge · Optional"
options: (omit any method $repo_settings disallows; always include "Not now" last)
  - label: "Merge — <recommended-method> (Recommended)"
    description: "<what it does>; deletes remote branch <branch_name> after merge"
  - label: "Merge — <other-allowed-method>"
    description: "..."
  - label: "Not now"
    description: "Leave PR open — merge manually later"
```

On "Merge — X":
```bash
gh pr merge "$pr_number" --<merge|squash|rebase> --delete-branch
```
- exit 0 → report the merge SHA. Proceed to post-merge cleanup below.
- nonzero → report the `gh` error verbatim (base branch moved, unmet branch protection,
  conflict) and **STOP** — no retry, no silent fallback to a different method.

**Post-merge local cleanup (non-gated, automatic — only after exit 0 on the merge itself):**

```bash
git checkout "$default_branch"
git pull origin "$default_branch"
git branch -d "$branch_name" 2>/dev/null || git branch -D "$branch_name"
echo "Post-merge: switched to $default_branch, pulled, local branch $branch_name deleted."
```

The `-d`→`-D` fallback is expected after a squash/rebase merge (the local branch's commits
aren't byte-identical to what's now on `$default_branch`, so the safe delete correctly refuses);
force-deleting here is safe because `gh pr merge` already confirmed the merge succeeded
remotely — this is not the same risk class as force-deleting an unconfirmed branch. Wrap this
whole cleanup block in `|| true` (matches Step 5.5's established idiom) — never fail the flow
here, the merge itself already fully succeeded.

## Invariant guardrails

- **NEVER run `git commit` before the explicit click on the commit gate.**
- **NEVER commit directly to the default branch** — Step 3.6 must have either created a feature
  branch or confirmed one was already checked out before Step 5 runs.
- **NEVER `git push --force`** under any circumstances.
- **NEVER `git commit --no-verify`** — do not bypass hooks.
- **NEVER create empty commits** — check `git status` first.
- **NEVER commit `.env`, secrets, API keys** — if `git status` shows suspicious files (`.env`,
  `*secret*`, `*credential*`, `*.pem`), stop and warn the user before proceeding.
- **NEVER run `git add .` / `git add -A`** — Step 1's computed scope (`git add -u`, or the
  explicit paths from "Stage additional files") is the only staging path.
- **NEVER execute `gh pr merge` without the explicit click on the Step 7 merge gate** — CI green
  is a precondition to *propose* merging, never a license to merge automatically.
- **NEVER auto-fix a failing CI check** — Step 6c diagnoses and reports; the human decides and
  pushes the fix.
