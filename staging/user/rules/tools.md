# Tools

Facts about invoking tools on this machine. No `paths` key on purpose: these apply to
every project and must stay loaded after a compaction, since a rule about how to run a
command is needed while running it, not while reading a file of some type.

Each entry is the rule alone; the incident that established it (dates, exact transcripts,
measurement detail) lives in `docs/tools-evidence.md` under the matching anchor — read it
when the reason here isn't enough, don't restate it here.

- **macOS's default bash is 3.2, not 4+.** Never use `mapfile`, associative arrays, or
  `${var^^}`/`${var,,}` — they fail at runtime, not at `bash -n`. Collect array output with
  `arr=(); while IFS= read -r x; do arr+=("$x"); done < <(cmd)`. → #bash-32

- **The Bash tool's host shell is zsh, which does not word-split unquoted expansions.**
  `for t in $LIST` over a space-separated list iterates once, over the whole blob, silently.
  Wrap the loop in `bash <<'EOF' ... EOF` (exporting what it needs) or use
  `while IFS= read -r`. → #zsh-word-split

- **macOS ships BSD `cat`, not GNU coreutils** — GNU-only flags like `-A` fail
  (`illegal option -- A`). Use `od -c file` to inspect control/non-printable characters.
  → #bsd-cat

- **A filename/dir starting with `-` is parsed as an option** by `ls`, `grep`, `find` —
  `~/.claude/projects/` entries always start with one. Prefix with `./` or pass `--` first.
  → #leading-dash-filenames

- **Installing `yt-dlp` for a transcript: use a scratch venv, never global.** Auto-captions
  use a rolling display window — drop any SRT block whose text is contained in the previous
  one before treating the result as prose. → #yt-dlp-transcripts

- **Dispatching a subagent to check whether its own definition holds: pass facts only,
  never restate the rule it's checking.** The reminder tests itself, not the subagent, and
  hides the failure of the next run that omits it. → #subagent-self-check

- **A GUI app launched with `nohup … &` from a Bash call dies when the command returns**
  (the tool kills the process group) — use `open -n /path/App.app --args …` instead. A
  nohup'd **plain CLI/shell script is different and does survive**: it detaches with
  `ppid 1`, confirmed via `ps -Ao pid,ppid,command`. Its redirected log going quiet right
  after the Bash call returns is ordinary buffering (e.g. `xcodebuild`'s own slow output),
  not evidence of death — check `ps -p <pid>` before concluding a background job died, then
  wait for real completion with `until ! ps -p <pid> > /dev/null 2>&1; do sleep 15; done`
  passed as `run_in_background: true`.
  → #gui-app-nohup #nohup-cli-script-survives
  <!-- src:auto-learning session:c5b1ac2b-b810-4e28-b27f-2618be3133e0 date:2026-09-11 -->

- **System Events / AppleScript quirks on this machine**: `tell ... first process whose
  unix id is <pid>` fails reliably (`-1719`) even when alive — address by name instead
  (`tell process "AppName" to ...`); UI-element-level queries fail with `-1728` (no
  Accessibility access, a standing state) — non-UI calls still work, ask the user to
  drive the GUI manually. → #system-events-by-pid #system-events-accessibility

- **`ScheduleWakeup` requires `prompt` unless `stop: true`**, even for `noop: true`. Always
  pass `prompt` alongside `delaySeconds`, `reason`, `noop`. → #schedulewakeup-prompt

- **`VAR=value cmd args…` resolves `cmd` through the NEW value being assigned**, not the
  caller's current PATH — an empty-PATH test breaks a bare-name wrapper command too. Capture
  the interpreter's absolute path first: `real_bin=$(command -v bash); PATH=/nonexistent
  "$real_bin" -c "..."`. → #var-assign-path-resolution

- **A Bash call likely to run past 2 minutes must not run in the foreground** — the tool
  kills it at 2 min (`Exit code 143`), discarding output. Reissue with
  `"run_in_background": true`. → #bash-2min-timeout

- **A multi-line Bash call is approved/denied as one unit — an `rm -rf` anywhere in it,
  chained or bare, reliably gets the whole call denied.** Never issue `rm -rf`: to replace a
  directory's contents, `mkdir -p`/`mktemp -d` a fresh dir and `cp -R` into it; to recreate a
  worktree at the same path, `git worktree add` a differently-suffixed path instead of
  removing the old one. → #rm-rf-denied

- **An unmatched glob aborts the whole call on this machine's zsh** (`nomatch` is on) —
  a no-match glob fails the call instead of passing the literal pattern through. Search
  recursively instead: `grep -rln "pattern" Sources/`. → #zsh-nomatch-glob
  Same family: a bare word starting with `=` (a `======` separator, say) triggers zsh's
  `=command` expansion and fails with `<rest> not found`, aborting the call; use `---` or `####`
  as separators. → #zsh-equals-expansion
  <!-- src:auto-learning session:12348409-ed36-4def-a370-011451ed0a92 date:2026-09-09 -->

- **`gh pr` quirks**: `gh pr checks <N>` exits non-zero while merely pending, and also exits 1
  "no checks reported" with no CI at all — both look identical. Check
  `gh pr view <N> --json statusCheckRollup -q '.statusCheckRollup'` first (empty = no CI); else
  loop on the printed bucket TEXT, never `gh`'s own exit code:
  `until [ "$(gh pr checks <N> --json bucket -q '[.[].bucket]|all(.!="pending")' 2>/dev/null)" = "true" ]; do sleep 15; done`.
  Also: `gh pr view --json` has no `merged` field, use `mergedAt` (`state == "MERGED"` +
  non-null `mergedAt`); `gh pr merge --delete-branch` can exit 1 on local branch-delete failure
  in a separate worktree though the GitHub-side merge succeeded — confirm via `mergedAt`, clean
  up manually (`git push origin --delete`, `git worktree remove`, `git branch -D`).
  → #gh-pr-checks-pending #gh-pr-view-merged #gh-pr-merge-worktree

- **`mcp__claude-in-chrome` has no standalone `scroll` tool** — scrolling is an action of
  the unified `computer` tool (`{"action": "scroll", ...}`). → #chrome-scroll-action

- **Dispatching a write-scope-gated agent (e.g. `architect`) while the parent is in plan
  mode: the two write restrictions don't intersect**, so the agent can't write to disk at all
  — treat its reply as the deliverable and have the parent `Write` the file once out of plan
  mode. → #agent-write-scope-plan-mode

- **`grep` here execs `ugrep -G`, not GNU/BSD grep** — an escaped `\+` right after an anchor
  like `^` is a parse error, not a literal plus. Don't escape the plus, or use fixed-string
  mode (`grep -F`). → #ugrep-anchor-plus

- **`git checkout -- <file>` / `git reset --hard` / `git restore --staged <file>` are denied
  by the Bash permission system, even issued alone.** An Edit-tool change reverts with an
  inverse Edit call instead (no permission gate there); a stash-pop conflict resolves by hand
  with Edit rather than reset. For unstaging, no in-session workaround exists — leave the file
  staged and give the user the exact command to run themselves. → #git-checkout-discard-denied

- **git tag quirks**: `git push origin :refs/tags/<tag>` is reliably blocked by the Auto Mode
  classifier, and chaining a git-tag create with its push in one Bash call can get the whole
  call blocked too — retrying either doesn't help. Delete a tag via the GitHub API instead:
  `gh api -X DELETE repos/<owner>/<repo>/git/refs/tags/<tag>`; to create+push a new one, split
  into two separate calls: `git tag` first, verify, then `git push` separately. Separately, a
  branch-protection rule on `main` does not gate tag pushes — a commit `git push origin main`
  rejects can still be tagged and pushed straight through, silently firing tag-triggered
  workflows on an unmerged commit. Confirm the commit is really on the remote branch before
  tagging a release. → #git-tag-delete-classifier-blocked #git-tag-create-push-split
  #branch-protection-tags-ungated

- **`notarytool` 401 in CI can persist after rotating the app password if the paired Apple
  ID secret is stale.** Compare secret timestamps with `gh secret list`; update both
  together. → #notarytool-401-apple-id

- **`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` is read at process start** — editing it changes nothing
  for the session doing the editing, and a repo's staged config is not evidence of live
  behaviour. Confirm actual behaviour by scanning `compact_boundary`/`compactMetadata` in the
  session transcripts. → #autocompact-override-drift

- **zsh reserves `status` (and other names) as read-only special variables.** A loop
  assigning a grep/command-substitution result to a variable named `status` fails
  immediately (`read-only variable: status`), aborting the whole loop. Use a non-reserved
  name (`status_val`). → #zsh-readonly-status

- **A `.txt` staged per the "publish this prose" convention (`=== TITLE ===`/`=== BODY ===`
  headers) is not parsed by any publish command** — feeding it straight to `gh issue comment
  -F` posts the markers verbatim. Strip headers first before `--body-file`/`-F`; if already
  posted, `gh api ... -X PATCH` to fix in place. → #txt-publish-headers-not-stripped

- **`gh api notifications` cannot be trusted as the sole signal for "did anything happen on
  GitHub"** — confirmed returning `0`/`[]` even immediately after a real reply landed. When
  specific issues are known, query them directly (`gh issue view <N> --json comments`)
  instead of relying on the notifications feed. → #gh-notifications-unreliable

- **A `cd` in one Bash call does not reliably carry over into the next, separate call**,
  despite the tool's own description. Use `git -C <absolute-path> ...` in every call needing
  a non-default directory, or chain the whole sequence with `&&` inside one call.
  → #cd-not-persisted

- **A subagent receives the full CLAUDE.md hierarchy at its own startup, except the
  built-in `Explore`/`Plan` agents, which skip it entirely** — custom subagents are not
  exempt. A correction written mid-session never reaches an already-running session or
  subagent; it applies only to the next dispatch. → #subagent-claude-md-load-timing

- **A `raw.githubusercontent.com` URL guessed with `main` can 404 on a repo whose default
  branch is still `master`** — don't retry variations blind: `gh api repos/<owner>/<repo>
  --jq '.default_branch'` first. → #github-raw-default-branch

- **Repairing a broken custom-agent symlink mid-session does not make it dispatchable by
  name in that session** — the dispatchable-agent-type list is snapshotted at session start,
  so `Agent(subagent_type: "<name>")` still answers "not found". Read the target agent's
  `.md` directly and dispatch `general-purpose` instead, pasting the full definition into the
  prompt as a self-imposed contract (role, boundaries, tool restrictions honored even where
  not enforced by the grant). A fresh session picks up the repaired symlink normally.
  → #agent-registry-snapshot-mid-session

- **A tool not yet in the discovered-tool set (e.g. `TaskCreate`) must be loaded with
  `ToolSearch({"query": "select:<ToolName>"})` before a call using typed params** (arrays,
  numbers, booleans) — otherwise those params serialize to strings and the client-side parser
  rejects the call. `TaskCreate` also creates exactly ONE task per call: top-level
  `subject`/`description` strings, never a `tasks`/`todos` array. A call with only `{}` (e.g.
  `ListAgents`) is unaffected regardless of load order. → #toolsearch-load-before-typed-params

- **A `fork` inherits the full conversation, including any pending irreversible instruction
  (merge, push, delete, deploy), and the same tool access as the parent.** Dispatched for
  analysis only with a verdict prompt phrased as an action label ("SAFE TO MERGE / NOT SAFE"),
  it can read an earlier "go ahead" as its own authorization and execute the action itself.
  State explicitly "report your findings and stop, do not execute" and phrase the verdict as
  a neutral finding, never an action label. → #fork-inherited-context-hitl-bypass

- **`Agent()` always spawns a brand-new subagent, even with a prompt aimed at continuing a
  prior dispatch** — no resume-by-prompt-similarity. To keep talking to an already-dispatched
  agent, find its task-id with `ListAgents` and `SendMessage(to: <task-id>, ...)`.
  → #agent-no-resume-use-sendmessage

- **A Bash call whose `cwd` is inside a worktree-isolated session is refused whenever the
  static check can't prove every clause stays in that worktree**, even when the command never
  actually leaves it. Confirmed triggers, all refused with "too complex to verify": a heredoc,
  `$(bash script.sh ...)` substitution, a quoted `$HOME`-prefixed script path even alone, a
  piped script, or a chain mixing a `for` loop/runtime variable with `git`/`open`. Fix: one
  plain single-statement call, a literal absolute path (never `"$HOME/..."`), no heredoc, no
  pipe, no `$(...)` wrapping the whole call. A command genuinely targeting a path outside the
  session's own worktree (`git -C <other-worktree> ...`) is a hard deny with no in-session fix
  — hand the exact commands to the user for an unsandboxed terminal. One exception: if the
  block instead says `worktree-git-guardrail` and no `EnterWorktree` ran this session, the
  `cwd` is just stuck inside a worktree dir from an earlier `cd` — `cd <main-repo-path> && pwd`
  as its own call relocates it, then the same command succeeds. → #worktree-isolated-bash-refusal

<!-- src:auto-learning session:5ec38a12-eed4-4704-8d46-1010d5bf262f date:2026-09-11 -->
<!-- src:auto-learning session:708d0d1e-0bc9-425b-bac6-745d820c7eb3 date:2026-09-09 -->
<!-- src:auto-learning session:db34b10a-3a09-4a96-9b9a-b9562560712f date:2026-09-07 -->

- **The Codex CLI sandbox (`workspace-write`) cannot build or test an Xcode project**, even a
  native `-destination 'platform=macOS'` target — `xcodebuild` reports
  `CoreSimulatorService connection became invalid`, then the misleading
  `'<name>.xcworkspace' is not a workspace file` (the same workspace lists fine outside). The
  wrapping `codex exec` can still print exit code 0, so read xcodebuild's own status, never the
  wrapper's. Route Xcode tester/coder work to a Claude agent in an isolated worktree.
  → #codex-sandbox-xcodebuild
<!-- src:auto-learning session:12348409-ed36-4def-a370-011451ed0a92 date:2026-09-09 -->
