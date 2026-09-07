---
name: codex-audit-git-preconditions-and-path-shape
description: Measured git preconditions that do NOT hold (is-inside-work-tree passes in unborn and bare repos) and the relative-in/absolute-out path contract of codex-reviewer.sh audit mode
metadata:
  type: project
---

Measured on 2026-09-06 while fixing the cycle-2 review findings in
`staging/plugin/scripts/codex-reviewer.sh` (audit mode only).

**`git rev-parse --is-inside-work-tree` is NOT a precondition for anything.** Measured, not
recalled, in scratch repos:

| repo state | `--is-inside-work-tree` | `--show-toplevel` | `git diff HEAD` |
|---|---|---|---|
| unborn (`git init`, no commits) | prints `true`, exit **0** | works, exit 0 | **exit 128**, empty stdout |
| bare (`git init --bare`) | prints `false`, exit **0** | **exit 128** | n/a |
| normal | 0 | 0 | 0 |

Why it matters: the script guards audit and review mode with
`! git rev-parse --is-inside-work-tree >/dev/null 2>&1`, which tests the EXIT STATUS only — so it
passes in both degenerate states. Two comments in this repo had already reasoned "X cannot fail once
the is-inside-work-tree check has passed"; both were false. A guard that reads a command's exit code
while the command signals through stdout (`false`) is the rule-5 checker/reporter confusion in
git's own surface.

How to apply: never treat that check as licence to skip an exit-status capture on a later `git diff`
/ `git show` / `git rev-parse --show-toplevel`. Each capture is four lines and turns a silent empty
result into exit 3 (rule 4). If a comment in this repo claims a git call cannot fail, verify the
claim in a scratch repo before trusting it — a false premise written as a comment is what kept
finding 1 alive through a full review cycle.

**Audit mode's path shape is relative in, absolute out.** `enumerate-sources.sh` emits
`git ls-files` output (repo-relative), the prompt tells the model "file (the path, as given below)",
and `deep-refactor/SKILL.md`'s finding schema declares `"file": "<absolute path>"` because Gate 1
merges the array with Claude-`reviewer` findings and dedups on file + line + description. So the
formatter must join `REPO_ROOT` back on. Anything else flowing from `FILE_LIST` into the emitted
findings needs the same conversion; a repo-relative value looks perfectly valid and simply never
dedups against its Claude-side twin.

The id digest is deliberately kept on the REPO-RELATIVE value while `file` is emitted absolute, so
the same tree audited from a different checkout or worktree yields identical ids. If a future change
makes ids look unstable across worktrees, that pairing is the thing to check first.
