# ADR-0037: commit skill gains auto branch-creation, strict file-scoping, mandatory blocking CI check with diagnosis, and a merge gate

## Status

Accepted

## Context

Using `/commit` on a live session (closing the `review-triage-fix` cost-pilot work), three gaps
in the skill forced manual work outside its own process:

1. **No branch enforcement.** The session was on `main` when `/commit` was invoked. The skill has
   no step that checks or creates a feature branch, even though the project's own invariant is
   "always on a feature branch, never commit directly to main." `git checkout -b` had to be run
   by hand before invoking the skill.
2. **Blind file scoping.** Step 1's default behavior for "nothing staged" is `git add .`, which
   would have swept in an unrelated untracked file (`nightly-report.json`) present in the working
   tree at the time. Excluding it required an ad-hoc instruction passed as skill arguments rather
   than anything the skill itself surfaces or defaults to safely.
3. **No CI or merge handling.** Step 6 stops after opening a PR. Checking CI status and merging
   were both done entirely outside the skill (`gh pr view`, `gh pr merge`, then manual local
   cleanup: `git checkout main`, `git pull`, delete the local branch).

The user asked to close exactly these three gaps, with explicit constraints:
- Branch prefixes limited to three buckets: `feat` for feature work, `fix` for fixes, `chore` as
  the catch-all for mixed or otherwise uncategorizable changes.
- CI must always be checked once a PR exists, and it is **blocking** — a failure must trigger
  automatic root-cause diagnosis (fetch and summarize the actual failing log), never a bare
  "red/green" report and never an auto-fix.
- Merge must always be **proposed** through a gate with a recommended method, and must **never**
  execute without an explicit human click.

This project already has a directly relevant precedent: **ADR-0022** (`nightly-autopilot`)
decided that unattended `git push` and opening a PR are acceptable, but merge, force-push, and
any write to the default branch stay forbidden — "a pushed branch and an open PR are reversible;
a merge is not, so the merge stays human." This ADR must not relitigate or weaken that boundary;
it extends the same principle to the interactive `/commit` skill, which previously had no
merge-related capability at all (automatic or gated).

## Decision

Modify `staging/plugin/skills/commit/SKILL.md` (source of truth for the exact final text) as
follows:

1. **New Step 3.6 — automatic feature-branch creation, no gate**, inserted after message
   generation (Step 3/3.5) and before the commit approval gate (Step 4). Detects the current
   branch against a **dynamically resolved** default branch (`git symbolic-ref
   refs/remotes/origin/HEAD`, with `gh repo view`/local-ref fallbacks — replacing a hardcoded
   `"main"` reference that existed in the old Step 6). If on the default branch or detached HEAD:
   computes a prefix from the commit's Conventional Commit `type` (`feat`→`feat`, `fix`→`fix`,
   every other type — `refactor`/`docs`/`test`/`chore`/`perf`, or a genuinely mixed change —
   →`chore`), derives a slug from the subject reusing `concept-to-code`'s exact topic-slug rule
   (`^[a-z0-9-]{1,40}$`, `concept-to-code/scripts/manifest-init.sh:26`), resolves name collisions
   by suffixing, and runs `git checkout -b`. If branch creation fails: **stop the whole flow** —
   never fall through to a commit on the default branch. Runs even under `--autopilot` (there is
   no gate to skip here).
2. **Revised file-scoping (Step 1/4/5).** Default staged set becomes tracked-modified files only
   (`git diff --name-only HEAD`, staged via `git add -u` right before commit) — untracked files
   are never included by default, under any circumstance. The Step 4 gate now always shows an
   "Excluded — untracked" list alongside the included files, plus a new "Stage additional files"
   option that lets the human explicitly name paths to add (re-running the secrets check on them
   before staging). A state with zero included files but real untracked work is treated as
   pending work, not "nothing to commit" — the gate variant for that case simply omits "Approve"
   (never offers an empty commit).
3. **Revised Step 6 (PR).** Idempotency check first: reuse an already-open PR for the branch
   instead of asking to create a new one. The base-branch-exists check now uses the same
   dynamically resolved `default_branch` instead of a hardcoded `main`.
4. **New Step 6b — mandatory CI check.** Runs whenever Step 6 produced an open PR (never under
   `--autopilot`, matching Step 6's own gating). `gh pr checks --watch --fail-fast` with a bounded
   wait (three ~8-minute rounds, then an operational `AskUserQuestion` — never an unbounded loop).
   Determines which checks are actually required by reading the repository's own branch
   protection rules; if that call fails, every reported check is treated as required (fail-safe,
   never silently downgraded).
5. **New Step 6c — mandatory failure diagnosis, never auto-fix.** For every failing required
   check, extracts the run ID from its job link and fetches the real failure log
   (`gh run view --log-failed`), summarizing root cause per check in the response. Explicitly
   stops — Step 7 is never reached on red CI.
6. **New Step 7 — merge gate, proposed only.** Reached only after Step 6b reports fully green.
   Reads the repository's actual allowed merge methods (`gh api repos/{owner}/{repo}`) and its
   real merge history (`git log --merges`, or a documented parent-count approximation when
   history is linear) to recommend a method — never hardcoding "merge commit." Presents the
   recommendation via `AskUserQuestion`; executes `gh pr merge` **only** after the explicit click.
   On success, runs a non-gated automatic local cleanup (checkout default branch, pull, delete
   the local branch — falling back from `-d` to `-D` since the remote merge is already confirmed).
7. **New invariant guardrails**: never commit directly to the default branch, never `git add .`/
   `git add -A`, never run `gh pr merge` without the Step 7 click, never auto-fix a failing check.

## Alternatives considered

- **Auto-merge once CI is green, no gate.** Rejected outright — directly contradicts ADR-0022's
  established boundary that merge is the one action in this system's git lifecycle that must
  always stay human, because it is the one action in the sequence that isn't cleanly reversible.
  Nothing in this change reopens that question; Step 7 only ever proposes.
- **Hardcode "squash" or "merge commit" as the universal recommended method.** Rejected. This
  repo's own merge history (`git log --merges --oneline`) is 100% merge commits, and all three
  methods are allowed at the repository level (`gh api repos/istefox/vibe-coding-system` →
  `allow_merge_commit`/`allow_squash_merge`/`allow_rebase_merge` all `true`) — but the skill runs
  across different repositories with different conventions and settings, so the recommendation
  must be derived per-repo (settings first, then actual merge history, then a documented
  parent-count approximation on linear history) rather than fixed.
- **Skip CI entirely and let the user check manually.** Rejected — the user explicitly required
  CI to always be checked and to block the merge proposal, with automatic diagnosis on failure
  rather than a bare pass/fail signal, matching this project's broader "never disable a test to
  make it pass; explain why in chat first" discipline extended to CI failures encountered here.
- **Branch prefix per full Conventional Commit type (`feat`/`fix`/`refactor`/`docs`/`test`/
  `chore`/`perf`, seven buckets)**, matching the literal wording of the project's own branch
  convention ("Branch: `type/short-description`"). Rejected in favor of the user's explicit,
  narrower instruction: three buckets for branch naming specifically (`feat`/`fix`/`chore` as
  catch-all), while the commit message's own `type` field keeps the full seven-value set
  unchanged. This is a deliberate simplification scoped to branch naming only, not a change to
  Conventional Commit typing.
- **Add a lightweight test harness for the commit skill in this same change.** Rejected as
  out of scope. `commit/` is a pure-Markdown skill with no `scripts/` directory, unlike most
  other skills in this repo that carry a hermetic test harness. Building one would mean
  extracting the bash logic into independently invokable scripts (e.g. a dry-run env var that
  no-ops every mutating `git`/`gh` call) — a real structural change, deliberately left as
  separate future work rather than bundled here.

## Consequences

**Positive:**
- The project's own "never commit to the default branch" invariant is now actually enforced by
  the skill itself, for every caller — including `concept-to-code`'s Step 7, which never created
  a persistent branch of its own before invoking `commit`.
- File scoping can no longer silently sweep in unrelated untracked files; the human always sees
  an explicit excluded list and must opt in per-path to add anything from it.
- CI status and merge readiness are now visible and diagnosed inside the same flow that created
  the PR, instead of requiring the user (or the assisting session) to switch to raw `gh` commands
  for the rest of the cycle.
- The merge-method recommendation is grounded in the actual repository's settings and history
  instead of a single hardcoded default, so it stays correct across repositories with different
  conventions.

**Negative:**
- The skill's bash logic grows substantially (three new/revised steps, one shared
  default-branch-detection block reused three times) without a corresponding test harness — a
  deliberate, disclosed scope boundary (see Alternatives), not an oversight, but it does mean
  regressions in this logic would only surface through live use, not a hermetic suite.
- The CI-wait step introduces real wall-clock time into `/commit` invocations that open a PR
  (up to ~24 minutes across three bounded rounds before the flow asks what to do next); this is
  the deliberate cost of making the check mandatory and blocking, per the explicit requirement.
- The merge-method approximation on repositories with linear history (parent-count heuristic to
  distinguish squash from rebase) is documented as an approximation, not a guarantee — a
  repository whose merged-PR sample happens to be misleading could get a suboptimal (but never
  unsafe, since it's still gated) recommendation.

**Neutral:**
- `--autopilot` mode is unaffected in practice (Step 6, the sole entry point to 6b/6c/7, was
  already skipped there) — the new steps carry an explicit defense-in-depth restatement of that
  exclusion rather than relying solely on the existing gating to keep them unreachable.

## References

- `staging/plugin/skills/commit/SKILL.md` — full implementation, source of truth for exact text
- `docs/architecture/ADR-0022-nightly-autopilot-goal.md` — "merge stays human" precedent this
  ADR extends rather than reopens
- `staging/plugin/skills/concept-to-code/scripts/manifest-init.sh:26` — topic-slug regex reused
  verbatim for branch slugs
- `~/.claude/plans/bubbly-imagining-teapot.md` — approved implementation plan for this change
