# Tools rule evidence

The narrative behind each rule in `staging/user/rules/tools.md` (deployed to
`~/.claude/rules/tools.md`): the incident, dates, exact transcripts, and measurement detail
that established it. Read this when a rule's one-clause reason isn't enough; the rule file
itself states the reason and does not restate this.

This is a historical record and is not corrected in place (repo rule 14) — a later
correction is appended as a dated `## Correction` under the relevant section, not edited
into the original entry.

Not loaded by anything: `docs/` is outside `staging/sync-to-claude.sh`'s `PAIRS` list, so
this file never deploys and is looked up, not read on every session the way the rule file
is. Every heading below is referenced by at least one `→ #anchor` in `tools.md`, checked by
`staging/plugin/scripts/tests/tools-rule-evidence-anchors.test.sh`.

## bash-32

macOS ships bash 3.2 as `/bin/bash` and as the default `#!/usr/bin/env bash` target; bash 4+
exists only if installed via Homebrew and placed earlier in PATH.

## zsh-word-split

On 2026-08-21 a suite runner reported `HARNESSES PASS=0 FAIL=1` naming one "test" whose name
was all 86 harness names concatenated, and nothing errored — `for t in $LIST` over a
space-separated list had iterated once, over the whole blob, because the host shell (zsh)
does not word-split an unquoted expansion the way bash does. The same bite is recorded
inside vibe-coding-system as ADR-0133 for the bash fences in `SKILL.md` files; it belongs
here too because it is a property of the tool, not of that repo.

## bsd-cat

Confirmed: `cat -A` fails with `illegal option -- A` on this machine.

## leading-dash-filenames

Entries in `~/.claude/projects/` are named after the project path with `/` turned into `-`,
so they always start with one — this is where the failure mode is most likely to bite.

## yt-dlp-transcripts

Auto-captions use a rolling display window, so drop any SRT block whose text is contained in
the previous one before treating the result as prose, or the transcript duplicates itself.

## subagent-self-check

A dispatched subagent-definition check that restates the rule being verified tests itself,
not the subagent under test, and this hides the failure of the next run that omits the
restatement — the check needs to hand over facts only (what happened), never the rule text
the subagent's own instructions already carry.

## gui-app-nohup

Three instances were lost to this before the cause was read out of the unified log rather
than guessed (`log show --predicate 'processImagePath CONTAINS "App.app"'`), which is also
where a window that vanished with no crash report explains itself:
`performKeyEquivalent:` → `terminate:` is somebody's Cmd+Q reaching an app that had just
stolen the focus. That `log show --predicate` command is itself worth a script file: inlined
into a Bash call, with its nested single and double quotes, it failed twice with
`too many arguments`; written to a `#!/bin/bash` file and run, it worked first time.

## system-events-by-pid

Fails reliably with `Impossibile ottenere process 1 whose unix id = <pid>. Indice non
valido. (-1719)`, even when `ps` confirms the pid is alive.

## system-events-accessibility

Fails with `System Events ha trovato un errore: osascript non ammette l'accesso di
assistenza. (-1728)`: the process hosting the Bash tool has no Accessibility permission
granted, and this is a standing state that persists across sessions, not a per-script fluke.
Non-UI System Events calls still work without it (`get name of first process whose
frontmost is true`, `tell application id "..." to quit`).

## schedulewakeup-prompt

Fails with `` `prompt` is required when `stop` is not true. ``.

## var-assign-path-resolution

`bash -c 'PATH=/nonexistent bash -c "echo hi"'` fails with `bash: bash: command not found`
(exit 127) before ever reaching `echo`, because the wrapper `bash` invoked by bare name also
resolves through the new, broken PATH.

## bash-2min-timeout

Confirmed twice in the same session: a foreground 87-harness suite run and a foreground
`verify.sh` run both hit 143, then both completed cleanly (`exit_code: 0`) once relaunched
in the background, collected with `TaskOutput({task_id, block: true, timeout: 300000})`.

## rm-rf-denied

The failure reads as `Permission to use Bash with command … has been denied`, quoting the
entire multi-line command — even a scratch temp file under `/var/folders/…T/` triggers it.
Issuing `rm -rf` "on its own", with nothing chained after it, does NOT reliably avoid the
denial — a bare, unchained `rm -rf <path>` gets denied on its own merits just as often
(confirmed 2026-08-23 and twice more on 2026-08-24, one of them a
`rm -rf <path> ; git worktree add <path> …` recreate chain).

## zsh-nomatch-glob

`grep -n "..." Sources/Connector/VaultAPI*.swift` with no matching file fails with
`(eval):2: no matches found: Sources/Connector/VaultAPI*.swift` instead of the bash
behavior of passing the literal pattern through to the command (`nomatch` is on by default
in this zsh).

## gh-pr-checks-pending

The same casing applies to the machine-readable `--json bucket` field, not just the printed
table: a poll loop comparing against `"PENDING"` (uppercase) never matches and exits
immediately, reporting all-clear on a PR that still has checks running. Confirmed the
lowercase single-shot background loop (`until gh pr checks <N> --json bucket -q
'[.[].bucket] | all(. != "pending")' 2>/dev/null | grep -q true; do sleep 15; done; echo
"ALL CHECKS DONE"`) avoids both the case bug and the repeat-notification failure a
hand-rolled `Monitor`-based dedup loop hit in the same session.

## gh-pr-view-merged

`gh pr view <N> --json ...` with `merged` in the field list fails outright with
`Unknown JSON field: "merged"`.

## gh-pr-merge-worktree

Fails with `failed to delete local branch … used by worktree at <path>` — the PR merge on
GitHub's side still succeeds; only the local cleanup step failed.

## chrome-scroll-action

`No such tool available: mcp__claude-in-chrome__scroll` — scrolling is
`mcp__claude-in-chrome__computer {"action": "scroll", "tabId": <id>, "coordinate": [x, y],
"scroll_direction": "down", "scroll_amount": N}`.

## agent-write-scope-plan-mode

Confirmed 2026-08-23 dispatching `architect` to draft an ADR while the parent was
mid-plan-mode: plan mode confines the parent to writing only `~/.claude/plans/…`; the
`agent-write-scope` hook confines `architect`'s own writes to `docs/architecture/**` and
`docs/superpowers/plans/**`. The two write restrictions don't intersect. The agent's own
words: "Non posso scrivere alcun file in questo turno: la plan mode mi consente solo
`~/.claude/plans/…`, e l'hook `agent-write-scope` me lo nega perché fuori da
`docs/architecture/**` e `docs/superpowers/plans/**`. Le due restrizioni non hanno
intersezione."

## ugrep-anchor-plus

`grep -n '^\+.*NEEDLE' file` fails with `ugrep: error: error at position N … invalid
syntax`, while the unescaped `^+.*NEEDLE` works because there ugrep reads `+` as a literal
character (confirm the shell function with `type grep`). For a diff's added lines (the `^+`
prefix), prefer `git diff A..B -- path | grep -F -B2 '+' | grep "NEEDLE"` over
`grep -B2 "^\+.*NEEDLE"`.

## git-checkout-discard-denied

`git reset --hard HEAD` gets the identical denial, confirmed both bare and chained inside a
longer branch-recreation sequence (`git checkout main && git branch -D ... && git checkout
... && git stash pop`). For the case that actually needs it — backing out of a
`git stash pop` merge conflict — locate the conflict with
`grep -n "^<<<<<<<\|^=======\|^>>>>>>>" <file>`, then resolve each hunk by hand with Edit.

## git-tag-delete-classifier-blocked

`Permission for this action was denied by the Claude Code auto mode classifier. Reason:
Blocked by classifier.` — retrying the identical command does not help, and it is a
different gate than the ordinary Bash permission system. Confirmed working after two
straight classifier blocks on the git form; verify with
`git ls-remote --tags origin | grep <tag>`.

## git-tag-create-push-split

`Stage 2 classifier error - blocking based on stage 1 assessment` — despite the message's
own "usually transient" hint, blindly retrying the same combined call does not reliably
clear it: neither command had run (`git tag | grep <ref>` afterward showed nothing).
Confirmed: both went through once separated into two Bash calls.

## branch-protection-tags-ungated

A commit `git push origin main` rejects with `GH006: Protected branch update failed ...
Changes must be made through a pull request.` can still be tagged and pushed straight
through (`git tag v1.2.3 <sha> && git push origin v1.2.3`), silently firing any
tag-triggered workflow (`on: push: tags:`) on a commit never actually merged onto the
protected branch.

## notarytool-401-apple-id

Confirmed: `NOTARYTOOL_PASSWORD` was freshly rotated (`gh secret list` showed a same-day
timestamp) but notarization kept 401'ing; the paired `APPLE_ID` secret was 2+ months stale
(generated against a different Apple ID than the new password). Fix was updating both
together, then `gh run rerun <id> --failed`.

## autocompact-override-drift

Confirmed missing from the live file on 2026-08-25 despite being staged in a project's own
repo copy (`staging/user/settings.json`) since a prior PR that lowered it `70` → `50`:
because that project deliberately excludes `settings.json` from its own automated deploy
script (by design, so a human reviews it), the manual apply step was simply never done, and
nothing detected the drift. Effect: sessions ran on the CLI's internal default and compacted
only at ~94-95% of a 600k `autoCompactWindow` (measured via `compactMetadata.preTokens`,
four consecutive sessions, all `trigger: auto`, 566k-573k tokens) instead of the intended
50%, silently wasting tokens for weeks. Read the live value directly with
`python3 -c "import json; print(json.load(open(p))['env'])"`; scan `type: system,
subtype: compact_boundary` records' `compactMetadata` (`trigger`, `preTokens`) across
`~/.claude/projects/<project-slug>/*.jsonl` to confirm actual behaviour; diff a staged
settings file against the live one whenever a project deliberately keeps `settings.json`
out of its own sync script.

## zsh-readonly-status

`(eval):N: read-only variable: status` aborts the whole loop rather than just that
iteration, because `status` aliases `$?` in zsh. Confirmed: renaming `status`→`status_val`
and `step`→`step_val` in an otherwise identical loop ran cleanly.

## txt-publish-headers-not-stripped

Happened on issue #517's reply, caught only by reading the comment back
(`gh issue view <N> --json comments -q '.comments[-1].body'`). Strip the header lines first
— `tail -n +4 file.txt > /tmp/clean.txt` for the two-header layout, or a proper per-marker
split for others — before passing the result to `--body-file`/`-F`. If a bad post already
went out: `gh api repos/<owner>/<repo>/issues/comments/<id> -X PATCH -F body=@clean.txt
--jq '.html_url'` edits it in place.

## gh-notifications-unreliable

Confirmed four times in one session (`gh api notifications --jq 'length'`, and once with
`--paginate`): it returned `0` / `[]` every time, including once checked *immediately
after* a real reply had landed on the user's own watched repo, and again while a real
comment existed on a third-party repo the user had filed an issue on. Root cause not
diagnosed (token scope, read-state, or something else).

## cd-not-persisted

Confirmed: `cd .claude/worktrees/<x> && git add -A` in one call, then a bare `git commit`
with no `cd`/`-C` in the very next call, ran back in the original repo root — it silently
failed committing nothing there instead of committing inside the worktree.

## subagent-claude-md-load-timing

Confirmed 2026-08-27 against live docs (`code.claude.com/docs/en/sub-agents`,
`.../memory`), per the rule to verify tool/SDK behaviour from the live source rather than
training-data memory. The built-in `Explore` and `Plan` subagents skip the full CLAUDE.md
hierarchy — global `~/.claude/CLAUDE.md`, project CLAUDE.md, `CLAUDE.local.md`, managed
policy files — entirely, with no frontmatter field or per-agent setting to change which
agents skip them. Custom subagents (`~/.claude/agents/*.md`, e.g. `architect`, `coder`,
`reviewer`) are not the exception and load the hierarchy the same way the main session does.
Consequence: a correction written by `auto-learning` (or any edit to CLAUDE.md/rules)
mid-session never reaches a session or subagent already running — the hierarchy is read
once, at that entity's own startup, so the correction applies only to the *next* dispatch or
session, never the current one.

## github-raw-default-branch

A `raw.githubusercontent.com/<owner>/<repo>/main/<path>` URL built by guessing the branch
name 404'd because the target repo's default branch was still `master`, not `main` —
guessing cost a failed fetch and a second round-trip to re-derive the right URL. The fix is
to never guess: `gh api repos/<owner>/<repo> --jq '.default_branch'` first, then interpolate
that answer into the raw URL. Landed in `~/.claude/rules/tools.md` via auto-learning on
2026-09-03/04 but never backported to this repo's `staging/user/rules/tools.md` at the time,
which is the drift ADR-0191's audit (`sync-to-claude.sh` dry run) surfaced and this repo's
own catch-up commit (`769d5c3`) resolved.

## agent-registry-snapshot-mid-session

A custom subagent's `.claude/agents/<name>.md` symlink was found broken and repaired
mid-session, but `Agent(subagent_type: "<name>")` still answered "Agent type '<name>' not
found" for the rest of that same session — the dispatchable-agent-type list is snapshotted
at session start, not re-read live, so a symlink fixed after start never becomes
dispatchable-by-name until a fresh session picks it up. Workaround used: read the target
agent's own `.md` definition directly with Read and dispatch `general-purpose` in its place,
pasting the full definition (role, boundaries, tool restrictions) into the prompt so the
stand-in honors the same contract even where the harness does not enforce it. Landed in
`~/.claude/rules/tools.md` via auto-learning on 2026-09-03/04, backported here the same way
as `github-raw-default-branch` above.

## toolsearch-load-before-typed-params

A deferred tool (`TaskCreate`) was called with typed parameters — an array, a number, a
boolean — before its schema had been loaded via `ToolSearch`. The client-side parser
serialized every typed field to a string instead of rejecting the call outright, so the
failure surfaced downstream as a subtly wrong call rather than an immediate error. Calling
`ToolSearch({"query": "select:<ToolName>"})` first loads the real schema and the call
succeeds normally. `TaskCreate` has a second, independent trap: it creates exactly ONE task
per call — top-level `subject`/`description` strings, never a `tasks`/`todos` array passed
in one shot. A call carrying only `{}` (e.g. `ListAgents`, no fields at all) is unaffected by
load order either way, since there are no typed params to mis-serialize. Landed in
`~/.claude/rules/tools.md` via auto-learning on 2026-09-07 (session
`db34b10a-3a09-4a96-9b9a-b9562560712f`), backported here in PR #575.

## fork-inherited-context-hitl-bypass

A `fork` dispatched for read-only regression analysis, inside a conversation that also
carried a pending, already-approved merge instruction ("mergia, ma prima verifica eventuali
possibili regressioni" — merge it, but first check for regressions), executed the merge
itself instead of reporting back. A fork inherits the FULL conversation, including the
user's earlier "mergia", and the SAME tool access as the parent — not a restricted, read-only
one — so it treated the inherited instruction as its own authorization once it found no
regressions. The prompt made this worse by asking for a verdict phrased as an action label,
"SAFE TO MERGE / NOT SAFE", which primed the fork toward completing the action rather than
just reporting on it. Outcome was clean (no real regression existed) but the process
bypassed the intended human checkpoint of reviewing the findings before an irreversible
action ran. Fix: state explicitly in the fork prompt, "report your findings back to me and
stop — do not execute the action yourself, regardless of what the inherited context implies
is authorized," and phrase the requested verdict as a neutral finding ("regression risk:
none found / found"), never an action label. Applies to every fork, not just this repo —
forks always inherit full tool access, so the scoping has to happen in the prompt, not in a
tool restriction. Incident: vibe-coding-system PR #570, 2026-09-07. Landed in
`~/.claude/rules/tools.md` via auto-learning the same day (session
`db34b10a-3a09-4a96-9b9a-b9562560712f`), backported here in PR #575.

## agent-no-resume-use-sendmessage

`Agent()` always spawns a brand-new subagent, even when the prompt is explicitly aimed at
continuing a prior dispatch — there is no resume-by-prompt-similarity, and a second `Agent()`
call sharing the same intent produces an unrelated agent with no memory of the first one's
work. To keep talking to an already-dispatched agent, running or finished, find its task-id
with `ListAgents` and use `SendMessage(to: <task-id>, message: ...)` instead of calling
`Agent()` again. Landed in `~/.claude/rules/tools.md` via auto-learning on 2026-09-07 (session
`db34b10a-3a09-4a96-9b9a-b9562560712f`), backported here in PR #575.
