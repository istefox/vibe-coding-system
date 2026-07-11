---
name: commit
description: Use this skill for ANY git commit request — including "commit", "commit and push", "create PR", "commit then PR". Generates a Conventional Commits message with explicit HITL approval gate before executing. Optionally pushes and creates a PR after commit. Reads context (diff, CLAUDE.md, ADR/manifest). NEVER commits before the explicit user click. Supersedes commit-commands:commit and commit-commands:commit-push-pr.
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

`--autopilot`: when present in args, **skip Step 4 HITL gate** and execute the commit immediately with the generated (and optionally humanized) message. Emit: `"Commit: autopilot — executing commit directly..."` before `git commit`. Step 6 (PR) is also skipped in autopilot mode. **Only set by project-conductor or c2c when `manifest.autopilot=true`** — never set manually unless you explicitly want unattended commits.

---

## Process

### Step 1 — Verify repo and state

```bash
git rev-parse --git-dir
```

If it fails: report "Not in a git repository" and stop.

```bash
git status --short
git diff --stat HEAD
```

- Empty output → report "Nothing to commit" and stop.
- Unstaged only (nothing staged): in the gate (Step 4) show all modified files as
  "will be included via `git add .`"; the user can abort to stage selectively.
- Staged + unstaged: include only staged files in the commit; mention unstaged as "not included".

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

### Step 3.5 — Humanize message (conditional, public repos only)

```bash
"$HOME"/.claude/skills/clean-public-repo/scripts/detect-public-remote.sh \
  "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
```

- Output `silent` → Step 3.5 silent, proceed to Step 4 with the message from Step 3.
- Output `public` → emit `"Public repo detected — humanizing commit message (Step 3.5)..."`, then invoke `/skill humanize-en` on the commit message (subject + body, inline text mode):
  - Pass subject and body as inline text.
  - The skill returns the humanized text (no write gate: inline mode).
  - If humanize-en reports "0 patterns / text is clean": the message is unchanged — use the original Step 3 message for Step 4.
  - If humanize-en returns a rewritten message: replace the Step 3 message with it.
  - **Immediately** proceed to Step 4 (AskUserQuestion HITL gate) — do NOT wait for additional user input after humanize-en returns.
- **NEVER** humanize after the "Approve" click in Step 4: what the user approves is what gets committed.

### Step 4 — HITL gate (AskUserQuestion, BLOCKING — human approval required)

Use `AskUserQuestion`. This decision requires explicit human approval — do NOT auto-answer or auto-complete this gate.

```
question: "Commit — Human approval required\n\n
  Proposed message:\n\n```\n<commit-message>\n```\n\n
  Files included (<N>):\n<file-list max 10 lines, then '... and N more'>\n\n
  Approve to execute the commit. Only you can authorize this."
header: "Commit · Approval"
options:
  - label: "Approve — execute commit"
    description: "Runs git commit with this message"
  - label: "Edit message"
    description: "Select Other and type the corrected message"
  - label: "Abort"
    description: "Do not commit anything — exit without changes"
```

**NEVER run `git commit` before the explicit "Approve — execute commit" click.**
**NEVER auto-answer or auto-complete the AskUserQuestion.**

### Step 5 — Execute commit (ONLY after "Approve" click)

```bash
# If there are unstaged files to include:
git add .
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

Use `AskUserQuestion`. This is an optional step — only proceed with push/PR after an explicit click.

```
question: "Create a Pull Request? (requires explicit approval)\n\nBranch: <current-branch> → <default-branch>"
header: "PR · Optional"
options:
  - label: "Yes — push + create PR"
    description: "git push origin <branch>, then PR via GitHub MCP"
  - label: "No — local commit only"
    description: "Done"
```

If "Yes":
1. `git push -u origin <branch>` (push only after explicit click)
2. Check if the base branch (`main`) exists on the remote — **required before opening a PR**:
   ```bash
   git ls-remote --exit-code origin refs/heads/main >/dev/null 2>&1 && echo "MAIN_EXISTS" || echo "NO_MAIN"
   ```
3. If `MAIN_EXISTS`: proceed with `mcp__github__create_pull_request`:
   - `title`: subject of the commit message
   - `body`: body of the commit message + ADR reference if present in context
4. If `NO_MAIN` (new/first push — `main` not yet on remote):
   - **Do NOT attempt `mcp__github__create_pull_request` or `gh pr create`** — it will fail.
   - Report: "Push succeeded to `<branch>`. Remote has no `main` branch — PR skipped. This is typical for a brand-new repo. To establish `main` and enable PRs, run: `git push origin <branch>:main`; then set `main` as the default branch on GitHub."

## Invariant guardrails

- **NEVER run `git commit` before the explicit click on the commit gate.**
- **NEVER `git push --force`** under any circumstances.
- **NEVER `git commit --no-verify`** — do not bypass hooks.
- **NEVER create empty commits** — check `git status` first.
- **NEVER commit `.env`, secrets, API keys** — if `git status` shows suspicious files (`.env`,
  `*secret*`, `*credential*`, `*.pem`), stop and warn the user before proceeding.
