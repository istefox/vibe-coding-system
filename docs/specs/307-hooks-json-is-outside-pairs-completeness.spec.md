# SPEC — hooks.json is outside PAIRS completeness by a deferred decision

Source: GitHub issue #307

## Objectives
1. Re-verify the premise the exclusion rests on, on the current Claude Code build: does Claude Code
   read a `hooks.json` at that location, and record the result with the build number as ADR-0068
   §F13–F18 requires of build-specific facts.
2. Determine what `staging/plugin/hooks/hooks.json` is for today and whether anything reads it.
3. Either bring the file inside the `PAIRS` completeness check, or move its exclusion out of the ADR
   and into a declaration the check itself can read.

## Scope
In: `staging/plugin/hooks/hooks.json`; the exclusion comment and `check_complete` call sites in
`pairs-completeness.test.sh`; `PAIRS` in `sync-to-claude.sh`; the build-stamped re-verification of
the premise and where that record lives.

Out: changing what any of the four hooks referenced inside `hooks.json` do
(`protect-files.sh`, `nightly-guard.sh`, `auto-format.sh`, `chain-memory-capture.sh`); restructuring
`PAIRS` into a directory-level sync (ADR-0043 defers that to its own ADR, and the reason stands: it
must decide what happens to a deployed file that disappears from staging); the hand-wired
`settings.json` hook entries, which are a separate deployment path.

## Stack
Bash 3.2 (macOS-portable) shell scripts under `staging/plugin/scripts/` and
`staging/plugin/skills/*/scripts/`; Markdown SKILL.md instruction files; awk predicates; a 68-file
`*.test.sh` harness under `staging/plugin/scripts/tests/` run by `.claude/test-cmd`; GitHub Actions
CI (`ci`, `markdownlint`, `links`). No application runtime. This issue additionally touches a JSON
configuration file (`staging/plugin/hooks/hooks.json`) and a live Claude Code build behaviour that
must be probed rather than assumed.

## Architecture
- `staging/plugin/hooks/hooks.json` — the excluded file. Today it declares four hook registrations
  against `${CLAUDE_PLUGIN_ROOT}/scripts/…`: `PreToolUse` on `Edit|Write` → `protect-files.sh`,
  `PreToolUse` on `Bash` → `nightly-guard.sh`, `PostToolUse` on `Edit|Write` → `auto-format.sh`,
  `PostToolUse` on `Bash` → `chain-memory-capture.sh`. It is the only file under
  `staging/plugin/hooks/`.
- `staging/plugin/scripts/tests/pairs-completeness.test.sh` — holds `check_complete` (the reverse
  direction ADR-0043 added: every file under a named `staging/` subtree must appear as a `PAIRS`
  src) and the comment stating the `hooks.json` exclusion. The subtrees it currently sweeps are
  `plugin/agents`, `user/rules`, `plugin/skills` (`*/SKILL.md`) and `plugin/scripts` (`*.sh`, with
  an exemption list). `plugin/hooks` is swept by nothing.
- `staging/sync-to-claude.sh` — `PAIRS`, the one-entry-per-file incremental deploy path, plus the
  `# pairs-zone-anomaly:` and `# deployed-only:` declaration conventions that show how an exclusion
  can be declared where a check can read it.
- `staging/plugin/scripts/{protect-files,nightly-guard,auto-format,chain-memory-capture}.sh` — the
  four scripts the file references; each already deploys through `PAIRS` on its own.
- `staging/user/settings.json` and `~/.claude/settings.json` — the hand-wired registration path this
  repository actually uses for its hooks, and therefore the comparison point for "does anything read
  `hooks.json`".
- `docs/architecture/ADR-0043-93-pairs-completeness.md` — the source of the exclusion; the quoted
  line number will have moved.
- `docs/architecture/ADR-0024-28-vendor-deployed-only-skills-and-hooks.md` — `PAIRS` stays
  one-entry-per-file, additive-only; directory-level sync needs its own ADR.
- `docs/architecture/ADR-0016-dynamic-workflows-step5.md` — the v2.1.154 precedent that the
  substrate moves, and the standing instruction to re-run a probe after a major build bump.
- `docs/architecture/ADR-0068-176-worktree-isolation-contract.md` §F13–F18 — the requirement that a
  build-specific fact is recorded with its build number.

## Data model
`hooks.json` is a JSON document with a top-level `hooks` object keyed by event name
(`PreToolUse`, `PostToolUse`), each holding an array of `{ matcher, hooks: [{ type, command }] }`
entries. If this feature adds a declaration for the exclusion, that declaration is a one-line marker
in a file the check reads, following the existing `# pairs-zone-anomaly:` / `# deployed-only:`
convention.

## API / Interfaces
- `check_complete <pairs-file> <staging-relative-dir> <name-pattern> [exempt-file]` — the reverse
  completeness check; the interface through which `plugin/hooks` would be covered.
- `PAIRS` in `sync-to-claude.sh` — `src dst` pairs; an entry for `hooks.json` would create a
  deployed file that has never existed, which is the substance of the deferred decision.
- The Claude Code plugin hook-registration contract — whether a `hooks.json` outside a plugin
  directory is read at all, and under what root `${CLAUDE_PLUGIN_ROOT}` resolves. This is the
  premise to be probed on the current build.

## UI flows
None.

## Edge cases
- The premise may have changed since ADR-0043: a build that now reads a `hooks.json` at that
  location turns the exclusion from a reason into a gap, and the opposite result must be recorded
  just as explicitly.
- Adding a `PAIRS` entry would *create* a deployed file that has never existed — a deployment
  change, not a coverage change, and potentially a double registration if the same hooks are already
  wired by hand in `settings.json`.
- Duplicate registration is the concrete risk: `protect-files.sh` and `auto-format.sh` are already
  live through the hand-wired path, so a second registration would run them twice per event.
- `${CLAUDE_PLUGIN_ROOT}` may not resolve outside a plugin installation, in which case the four
  commands would fail rather than fire.
- An exclusion declared in an ADR is invisible to the check; the same exclusion declared in a file
  the check reads fails loudly when it goes stale — the `# pairs-zone-anomaly:` precedent.
- An excluded file with an unverified premise reads as covered; ADR-0043's own finding was that the
  check's direction was the defect, and this is the one file the corrected check still cannot see.
- A build-specific finding is true of one build and of nothing else, so the record must carry the
  build number and the instruction to re-probe after a major bump.
- Per the repository's standing rules: any new assertion must be seen RED against a declared plant,
  and a checker must distinguish "did not run" from "found nothing".

## Success criteria
- [ ] R-01 — the premise is re-verified on the current build and the result recorded with the build
      number, as ADR-0068 §F13-F18 requires of build-specific facts.
- [ ] R-02 — the file is either covered, or its exclusion is declared where the check can read the
      declaration rather than in an ADR.
