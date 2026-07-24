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
/commit [context-hint] [--autopilot]
```

Optional `context-hint`: brief feature description for the commit body.
From the concept-to-code chain: `<topic-full-title> (ADR: <adr-path>)`.

`--autopilot`: when present in args, **skip Step 4 HITL gate** and execute the commit immediately with the generated message. Emit: `"Commit: autopilot — executing commit directly..."` before `git commit`. Step 6 (PR) is also skipped in autopilot mode. **Only set by project-conductor or c2c when `manifest.autopilot=true`** — never set manually unless you explicitly want unattended commits.

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
  one requires the explicit "Stage additional files" path in Step 4.
- Included set empty **and** `untracked` non-empty (only brand-new files exist, nothing
  tracked-modified or pre-staged) → this is real work, not "nothing to commit": proceed to
  Step 4 with 0 included files and the no-`Approve` gate variant described there, instead of
  reporting "nothing to commit".
- **Secrets check runs here**, over `staged ∪ tracked_modified ∪ untracked` (not just the
  included set): if any path matches `.env`, `*secret*`, `*credential*`, `*.pem`, stop and warn
  per the Invariant guardrails — even a file that would never be auto-included by default can
  still be requested explicitly in Step 4, so catch it before that door opens.

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

**Trigger:** current branch (`git branch --show-current`, empty string means detached HEAD)
equals `$default_branch`, or is empty.

```bash
current_branch=$(git branch --show-current)
if [ "$current_branch" = "$default_branch" ] || [ -z "$current_branch" ]; then
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
```

If branch creation fails: **STOP** — never fall through to Step 4/5 while still on
`$default_branch`. This step is what actually enforces "never commit to the default branch" for
every caller of this skill, including `concept-to-code`'s Step 7 (which itself never creates a
persistent branch before invoking `commit`).

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

```bash
# Stage the default scope computed in Step 1 (skip if something was already staged
# manually, or if "Stage additional files" in Step 4 already staged what was needed):
if [ -z "$staged" ]; then
  git add -u   # tracked modifications/deletions/renames ONLY — never untracked
fi
# Commit with approved message:
git commit -m "$(cat <<'COMMITMSG'
<commit-message>
COMMITMSG
)"
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

**Always Read `<project-root>/.claude/context.md` first** (even if you expect it not to exist):
the Write tool refuses to overwrite a file that was not read in the current session.
If the Read returns an error (file absent), ignore it and proceed to Write.

Write or overwrite `<project-root>/.claude/context.md` (create `.claude/` if missing):

```
## Status (YYYY-MM-DD)
**Branch:** <current-branch>
**Last commit:** <short-hash> — <commit subject>
**In progress:** <infer from branch name / open manifest step / remaining findings — or "—">
**Next:** <one line: most actionable next step — or "—">
**Open decisions:** <from in-progress manifest current_step / recent ADR / or "none">
```

Rules:
- Max 10 lines total. Factual — no speculation beyond what context provides.
- "In progress" / "Next": derive from branch name, manifest `current_step`, or commit body TODOs.
- "Open decisions": check `docs/manifests/` for a manifest with `status: in_progress`; if found,
  note `current_step`. Otherwise `none`.
- This file is read-only for the session-context-inject.sh hook at the next SessionStart —
  the model gets the context automatically without the user having to re-explain.
- Emit one line after writing: `"Context → .claude/context.md"`.
- Wrap the whole step in `|| true` — never abort the commit flow if this fails.

### Step 6 — PR (optional, only after successful commit)

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
   - `body`: body of the commit message + ADR reference if present in context
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
not (see `ADR-0022`, `nightly-autopilot`'s "merge stays human" invariant — this step doesn't
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
