# SPEC — RTF's gitignore glob and this repo's own entry differ by a dash

Source: GitHub issue #287

## Objectives

1. Compare the literal glob written by `triage-state.sh commit` against the entry present in this
   repository's `.gitignore`, and determine **by running `git check-ignore`** which state files each
   rule actually covers — stated as a set of covered paths, not as a string diff.
2. Resolve the difference down to one rule covering the same set from both sides, rather than
   documenting the divergence.
3. Add an assertion that seeds a `.gitignore` differing from the script's own glob and proves the
   `check-ignore` branch is the one that runs.

## Scope

In: the glob written by `staging/plugin/skills/review-triage-fix/scripts/triage-state.sh`; the
`.triage-fix-last*` entries in this repository's `.gitignore`; the `git check-ignore` branch and its
exit-code handling; the assertion pinning that branch.

Out: the per-branch state-file design itself (ADR-0094 keeps it). Out: the basename argument
handling, which ADR-0094 already fixed and pinned via `T10b`. Out: the `.gitignore` of any target
project — this issue is about the script's rule and this repository's own entry.

## Stack

Bash 3.2 (macOS-portable) shell scripts under `staging/plugin/scripts/` and
`staging/plugin/skills/*/scripts/`; Markdown SKILL.md instruction files; awk predicates; a 68-file
`*.test.sh` harness under `staging/plugin/scripts/tests/` run by `.claude/test-cmd`; GitHub Actions
CI (`ci`, `markdownlint`, `links`). No application runtime.

## Architecture

- `staging/plugin/skills/review-triage-fix/scripts/triage-state.sh` — the `commit` path, which
  builds `glob="${pref}.triage-fix-last-*.json"` and appends it only when
  `git -C "$d" check-ignore -q -- "$(basename "$SF")"` reports the path is not already ignored.
- `/Users/stefer/Developer/vibe-coding-system/.gitignore` — measured at spec time, this repository
  carries **two** `.triage-fix-last` entries, not one: `.claude/.triage-fix-last*.json` and
  `.claude/.triage-fix-last-*.json`. The issue's premise is a single differing entry; the
  measurement must be re-run and the design must account for whichever entries exist then.
- `staging/plugin/scripts/tests/triage-state-gitignore.test.sh` — the existing harness, including
  `T10b`, whose two earlier drafts ADR-0094 records as having passed while pinning nothing.
- `staging/plugin/scripts/tests/plant-check.sh` — the plant registry runner (ADR-0108).
- `docs/architecture/ADR-0094-250-triage-state-gitignore-glob.md` — the source; the line-98 anchor
  will have moved, so anchor on a distinctive string rather than the number.

## Data model

The RTF state file: `<project>/.claude/.triage-fix-last-<branch>.json`, one per feature branch,
written by `triage-state.sh` and gitignored by the rule under discussion.

## API / Interfaces

`triage-state.sh commit` — the entry point that writes the state file and, when the path is not
already ignored, appends the glob. `git check-ignore` exit-code contract, as documented in
`commit/SKILL.md`: **1 means "not ignored", a clean result, not a failure**; non-zero takes the
append branch, the safe direction, and the append is idempotent.

## UI flows

None.

## Edge cases

- **Two rules covering different sets.** ADR-0094's fix depends on `check-ignore` reporting "already
  ignored" so the script does not append. If the script's glob and the repository entry cover
  different sets, a state file can be ignored by one and tracked by the other.
- **A tracked state file on a public repository names every feature branch ever reviewed** — the
  consequence that makes this more than tidiness.
- **A fixture must be chosen against the failure mode, not merely be plausible.** ADR-0094 records
  two dead drafts of exactly this assertion: seeding the script's own glob let the literal-grep
  fallback suppress the append so the `check-ignore` branch never ran; seeding `.claude/` covered
  the doubled path the old bug produced, so `check-ignore` said "ignored" for the wrong reason. The
  seed must differ from the script's own glob **and** not cover the doubled path.
- **`git -C` moves the cwd**, so a relative path would resolve a second time against the file's own
  directory; the script passes a basename for this reason.
- **A human may have written a broader rule by hand.** This is not hypothetical — this repository's
  own `.gitignore` is the evidence, which is why `check-ignore` is used rather than a literal grep
  for the script's own line.

## Success criteria

- [ ] R-01 — one rule, covering the same set from both sides, with the difference resolved rather
      than documented.
- [ ] R-02 — an assertion that seeds a `.gitignore` differing from the script's own glob and proves
      the `check-ignore` branch is the one that runs (ADR-0094 records that two earlier drafts of
      this assertion passed while pinning nothing).
