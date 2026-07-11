---
name: clean-public-repo
description: This skill should be used when a repo is being prepared for public
  release or already-public needs retroactive cleanup of tool markers. Performs
  audit + hybrid cleanup (report → remove on confirmation) of Claude Code tool
  traces in working tree and commit history. Two history strategies: fresh-history
  publish (default for already-public repos) and surgical rewrite (option 2, never
  default). Orchestrator-only — destructive git operations require explicit HITL.
  Triggers include "/skill clean-public-repo".
---

# `clean-public-repo` — Repo Audit and Cleanup for Publication

**Standalone skill** that performs audit + retroactive cleanup of a repo before
publication or on an already-public repo. Detects tool markers (trailers,
trace-comments, decorative strings/emoji, slop files) in the working tree and
commit history, generates a report with a COVERAGE & LIMITS section, and proposes
cleanup actions on user confirmation.

Fourth instance of the "standalone skill + chain gate" pattern (ADR-0011; prior art:
`design-brainstorm`, `review-triage-fix`, `web-e2e-test`).

---

## When to invoke

**Invoke this skill when:**
- A repo is being prepared for publication on GitHub and tool markers must be removed
  before the first push.
- An already-public repo contains tool trailers/comments/emoji that need retroactive
  removal.
- The `concept-to-code` chain Gate 0b detected a public GitHub remote and the user
  wants to start retroactive cleanup (the skill is recommended by the chain, not invoked
  automatically).
- The user requests "/skill clean-public-repo" or "audit tool markers".

**Do NOT invoke for:**
- Requirements gathering (that is `interview-driver`).
- Code review (that is `review-triage-fix`).
- Design brainstorming (that is `design-brainstorm`).
- Operations requiring an isolated sub-agent: this skill runs on the orchestrator
  (see §Orchestrator-only below).

---

## Orchestrator-only

**This skill always runs on the orchestrator. NEVER dispatch a sub-agent for
operations in this skill.** Rationale (ADR-0011 D2/D8, consistent with ADR-0010 D1,
ADR-0009):

- Surgical rewrite and fresh-history publish require explicit interactive HITL
  before force-push and before any destructive operation.
- A sub-agent in auto mode cannot present a blocking HITL gate.
- Destructive git operations (force-push, orphan branch publish, filter-repo apply)
  must pass through human approval; they are never automated.

The orchestrator guides the user step by step. The helper scripts are informational
auxiliaries (dry-run, report, graceful degrade) — mutating execution always belongs
to the user after confirmation.

---

## Ethical framing

**A design constraint, not an option.** This skill is designed to:

1. **Remove tool markers** (commit trailers, trace-comments, decorative
   strings/emoji): the goal is not to advertise the tool + holistic repo quality.
2. **Curate quality** of the repo (essential commits, concise docs, zero unnecessary
   files).

**NEVER falsify authorship.** After cleanup the commit remains correctly attributed
to the configured git author (e.g. Stefano). The skill does not attribute commits to
invented third parties, does not falsify dates, and does not deceive human reviewers
if someone explicitly asks. The work remains the user's: they direct it, review it,
test it, and are responsible for it. **No falsification of authorship. Never falsify authorship.**

Native tool attribution is already disabled at the configuration level
(`settings.json: attribution {commit:"", pr:""}`); this skill removes residual traces
that might still appear in content.

---

## Auto-detect public remote

Before proposing Gate 0b (from the chain) or the audit, run:

```bash
bash ~/.claude/skills/clean-public-repo/scripts/detect-public-remote.sh <project-root>
```

The detector operates with a **fail-safe cascade toward `silent`**:
1. Non-git → `silent` (no operations possible).
2. No remote → `silent`.
3. Non-github host → `silent` (SPEC R1 scope: GitHub; extensible in future).
4. `gh` absent or unauthenticated → `silent` (visibility not determinable; treated
   as non-public to avoid disturbing private repos).
5. `gh repo view --json visibility` == `PUBLIC` → `public` + `repo=<owner/repo>`.
6. `PRIVATE`/`INTERNAL`/error → `silent`.

Stdout: `public` (line 1) + `repo=<owner/repo>` (line 2) if public;
`silent` (line 1) in all other cases. Always exits 0.

**Principle:** propose the gate ONLY on GitHub remotes with confirmed `PUBLIC`
visibility via API. The indeterminate case is treated as non-public.

---

## Detection

Primary detection is **custom zero-dep grep** (bash 3.2-clean, stack-agnostic).
gitleaks is an **optional** integration with graceful degrade.

### Execution

```bash
bash ~/.claude/skills/clean-public-repo/scripts/detect-tool-traces.sh <project-root>
```

### Detected patterns

**Working tree** (tracked files via `git ls-files`; fallback `find` for non-git):
- Trailing / residual commit markers: `Co-Authored-By:.*Claude`,
  `Generated with.*Claude Code` → category `trailer`, severity `auto-removable`.
- Trace-comments: `(added|generated) by Claude`, `# generated by` →
  category `comment-trace`, severity `auto-removable`.
- `claude` strings + decorative emoji → category `string-emoji`,
  severity `auto-removable`; **but** if the match is in a dependency context
  (`claude-*` in package.json/requirements/import) → `string`, severity
  `review-needed` (possible false positive — not auto-removable).
- Slop files by name (`scratch*`, `*-COPY`, `notes.md`) → category `slop`,
  severity `manual` (human decision, never removed automatically).

**Commit history** (messages via `git log --format="%h %B"`):
- Same trailer/marker patterns → category `commit-trailer`,
  severity `auto-removable|<short-sha>`.

### Output format

Pipe-separated lines: `category|severity|location|match`

```
trailer|auto-removable|src/foo.py:12|Generated with Claude Code
string|review-needed|package.json:5|"claude-sdk": "^1"
slop|manual|scratch.md|slop filename: scratch.md
commit-trailer|auto-removable|a1b2c3d|Co-Authored-By: Claude
```

### Optional gitleaks

If `gitleaks` is present, it is used as a cross-check with custom rules for tool
markers (JSON output merged into the grep report). **If absent** (as in the current
environment): no error; note in report: "gitleaks not installed: lexical detection
via grep (bonus secret-scanning not available; install: `brew install gitleaks`)".
The minimal path works with `git` only.

---

## Hybrid action

**Principle: report first, remove only on per-category/per-item confirmation.**
**NEVER blind removal.** (SPEC R2)

Flow:
1. Run the detector → present findings grouped by category to the user.
2. For each `auto-removable` category: propose confirmation (`[y]` remove /
   `[s]` skip / per-item detail `[d]`).
3. For `review-needed`: show context (path:line + match), let the user decide
   (do not propose automatic removal — it could be a legitimate dependency).
4. For `manual` (slop): informational list; the decision to delete is entirely
   the user's.
5. Slop file removal requires **explicit confirmation** and must be flagged as
   "permanent deletion" (global HITL rule).

---

## Report contract

The skill writes a report to:
```
<project-root>/docs/clean-report/YYYY-MM-DD-<slug>.md
```
(creates the directory if absent)

### Report structure

```markdown
# Clean Report — <slug>

**Date:** YYYY-MM-DD
**Repo path:** <absolute path>
**Remote:** <owner/repo> (PUBLIC) | not determinable
**History strategy proposed:** fresh-history publish | surgical rewrite | none
**Audit result:** ready | needs-cleanup

## Findings

| Category | Severity | Location | Match |
|---|---|---|---|
| ... | ... | ... | ... |

## History Strategy

[recommendation and rationale]

## COVERAGE & LIMITS

**Scanned:** tracked text files (git ls-files) + commit messages.

**NOT covered:**
- Binary files and images
- Generated/minified files (build artifacts)
- Git metadata (author/committer dates — not falsified by design)
- Non-lexical semantic traces (writing style)
- Untracked / .gitignore'd files
- Secrets unrelated to tool markers

**Disclaimer:** this audit reduces known lexical markers. It does NOT guarantee
total indistinguishability and does NOT replace a human review.

## Proposed actions

[confirmable list by category]
```

**Result `ready`:** zero `auto-removable` findings remaining after a confirmed cleanup.

---

## History strategy — fresh-history publish (default for already-public repos)

**Default for already-public repos.** Avoids force-pushing to the original repo
entirely (top risk mitigated by design). (ADR-0011 D5)

### Helper script

```bash
bash ~/.claude/skills/clean-public-repo/scripts/fresh-history-publish.sh <root> [dry-run|prepare]
```

- `dry-run` (default): shows the plan without mutating the repo. Exit 0.
- `prepare`: executes non-destructive steps (tar backup, local orphan branch,
  staging) → then STOPs and instructs the orchestrator to present the HITL gate for
  commit/push. NEVER automatic.

### Flow (orchestrator guides the user)

1. **Mandatory backup** of `.git/`:
   ```bash
   tar -czf .git-backup-$(date +%Y%m%d-%H%M%S).tar.gz .git
   ```
   NEVER proceed without backup.

2. **Working tree cleanup** on confirmed `auto-removable` findings (see
   §Hybrid action) → clean commit on the current branch (not yet published).

3. **Orphan branch:**
   ```bash
   git checkout --orphan public-clean
   git add -A
   git commit -m "Initial public release"
   ```
   The original history (with traces) **remains intact and private** on the
   original branch.

4. **New derived public repo** (preferred):
   - If `gh` is present and authorized: `gh repo create <new-name> --public`
     (on explicit user HITL confirmation).
   - If `gh` is absent: manual instructions (create the repo on github.com → provide
     the URL).
   - Push only `public-clean`: `git push <new-remote> public-clean:main`.
   - **NO force-push to the original repo.** No suspicious gap, no corruption risk.

5. The original private history is never touched destructively.

### Safety notes

- `force-push` to the original repo is forbidden in this flow.
- Force-push (only to a NEW dedicated remote) requires **explicit user HITL
  confirmation** before any destructive push.
- The dry-run MUST be run before prepare (and shown to the user).

---

## History strategy — surgical rewrite (option 2, never default)

**Only as an explicit second choice**, deliberately requested by the user.
Suitable for repos not yet public or when preserving historical granularity is needed.
(ADR-0011 D6)

### Helper script

```bash
bash ~/.claude/skills/clean-public-repo/scripts/surgical-rewrite.sh <root> <patterns-file> [dry-run|apply]
```

- `dry-run` (default): shows what would change without mutating. Exit 0.
- `apply`: executes the rewrite on a fresh clone → then STOPs before force-push.

### Flow (orchestrator guides the user)

1. **Precondition: fresh clone.** `git-filter-repo` rejects non-fresh-clone repos
   by default; the skill respects this protection (NEVER pass `--force` to bypass it).
   The user must operate on a fresh clone:
   ```bash
   git clone <remote-url> <fresh-repo>
   cd <fresh-repo>
   ```

2. **Mandatory tar backup** of `.git/` (same as fresh-history).

3. **Always dry-run first:**
   ```bash
   git filter-repo --replace-text <patterns-file> --dry-run
   ```
   Shows what would change in files and commit messages. The user reviews the
   expected diff before applying.

4. **Automatic branch/tag backup** before application.

5. **Application** on the clone:
   ```bash
   git filter-repo --replace-text <patterns-file>
   ```
   (add `--message-callback` for trailers in commit messages if needed)

6. **force-push ONLY after explicit HITL** (`AskUserQuestion` / confirmation gate).
   This is a destructive remote operation (breaks clones/forks). **NEVER automatic,
   NEVER from a sub-agent.** The surgical-rewrite.sh script does NOT execute the
   force-push; it instructs the orchestrator to present the confirmation gate.

### Graceful degrade

If `git-filter-repo` is not installed:
- Message: "surgical rewrite disabled: `git-filter-repo` not found.
  Install: `brew install git-filter-repo` or `pip3 install git-filter-repo`.
  Use fresh-history-publish as an alternative."
- Exit 3. Fresh-history publish remains available (uses only core `git`).

---

## Dependencies and graceful degrade

| Dependency | Use | If ABSENT |
|---|---|---|
| `git` | core — always required | skill cannot operate on history; degrades to working-tree-only audit if possible; declares "non-git" and exits without error |
| `git-filter-repo` | surgical rewrite (option 2) | rewrite disabled (install message); fresh-history remains available |
| `gitleaks` | bonus secret detection (optional) | no error; note in report; grep detection remains active |
| `gh` | detect remote visibility (D1) + repo create (D5) | Gate 0b silent; D5 degrades to manual instructions |

**Minimal path** (custom grep + fresh-history via core git) works with `git` only.
Optional dependencies improve coverage, they do not enable it.

**Verified environment (2026-05-23):** `git-filter-repo` PRESENT
(`/opt/homebrew/bin`), `gitleaks` ABSENT, `git` PRESENT.

---

## Safety / fail-mode

**Every destructive operation is behind explicit HITL.** (ADR-0011 D8, ADR-0009)

- **HITL on:** rewrite apply, force-push, slop file deletion, derived public repo
  creation. NEVER automatic, NEVER from a sub-agent.
- **Backup before destructive:** tar of `.git/` before rewrite/fresh-history;
  branch/tag backup before rewrite apply.
- **Dry-run before apply:** the detector and both helper scripts show the plan
  before mutating anything.
- **force-push:** NEVER on the original repo in the fresh-history flow. On the new
  derived repo ONLY after explicit user HITL confirmation.
- **No deletions without confirmation:** slop files are reported, not automatically
  deleted (global rule "never delete files without explicit confirmation").
- **Fail-safe toward silent:** if remote visibility is not determinable, the gate
  does not activate (better to not disturb than to activate on a private repo).

---

## Coexistence

This skill is **orthogonal** to all agents and other skills:

- Does **NOT patch** `coder.md`, `architect.md`, other agents, other hooks, `settings.json`.
- The **anonymous mode in the chain** (`concept-to-code` Gate 0b + `anonymize` flag
  in the manifest) is separate and carried in **dispatch prompt-templates** (not in
  this skill). When `anonymize=false` (default) the chain is identical to today:
  zero regressions.
- This skill is **recommended** by the chain for retroactive cleanup of existing
  repos (not invoked automatically — the user chooses).
- `review-triage-fix`, `design-brainstorm`, `web-e2e-test`, `refactor-snapshot`:
  unchanged; no interaction.

---

## References

- ADR: `docs/architecture/ADR-0011-clean-public-repo-anonymize.md` (D1-D8)
- Scripts: `scripts/detect-public-remote.sh`, `scripts/detect-tool-traces.sh`,
  `scripts/fresh-history-publish.sh`, `scripts/surgical-rewrite.sh`
- Tests: `tests/run-tests.sh` (PASS=22: 11 structural anchors + 3 smoke detect-remote
  + 8 smoke detect-traces)
- Prior-art tooling: `git-filter-repo` (`--replace-text`, `--dry-run`,
  `--message-callback`); `git checkout --orphan`; `tar -czf` backup
- Memory: `feedback_bash32-constraint`, `feedback_hitl-and-security-discipline`,
  `project_concept-to-code-chain`
