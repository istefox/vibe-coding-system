# SPEC — Chain never regenerates a generated Xcode project (issue #470)

**Topic slug:** 470-chain-never-regenerates-xcode

## Objectives

On a Swift project scaffolded by `git-repo-init` under Tuist, the concept-to-code chain runs
`xcodebuild test` against a `.xcodeproj` that is gitignored and that nothing in the chain ever
regenerates. Source files arriving via merge, checkout, or a worktree are not in the stale target,
so their tests never run and every `tests_after` figure is measured against a project that does
not reflect the current tree.

This fix makes `detect-test-cmd.sh` regenerate a Tuist-managed Xcode project before testing it,
detect that stack from a tracked manifest instead of the gitignored artifact it produces, and
report an unambiguous DID-NOT-RUN state when the regenerator is unavailable — never a silent
fall-through to a stale project.

## Scope

In scope:
- `staging/plugin/scripts/detect-test-cmd.sh`: new detection branch for a Tuist-managed project
  (`Project.swift`, `Tuist.swift`, or `project.yml`, tracked), emitting a `tuist generate &&`
  regeneration prefix ahead of the `xcodebuild test` command. The existing `*.xcodeproj` glob
  branch stays as-is and is checked only when no Tuist manifest is found (fallback for a tracked,
  hand-maintained `.xcodeproj` with no Tuist).
- Fix the `Package.swift` root-only check inside the same script's swift-package branch to also
  recognize `Tuist/Package.swift`, closing the worktree-visibility gap described in the issue (a
  worktree with `baseRef: head` has neither the gitignored `.xcodeproj` nor `.claude/test-cmd`,
  and under Tuist the manifest lives at `Tuist/Package.swift`, not root).
- A DID-NOT-RUN convention for the generated command itself: when the regeneration tool is absent
  from `PATH` at test-cmd execution time, the command must exit a value distinct from both a clean
  pass and an ordinary test failure, so `stop-gate.sh` and the chain's own gates (which already
  distinguish DID-NOT-RUN from clean, per this repo's rule 4) read it correctly rather than as a
  regression in the code under test.
- Documentation: `docs/architecture/ADR-NNN-470-chain-never-regenerates-xcode.md` recording the
  regeneration-prefix decision, the TOFU cost it imposes (an existing trusted `.claude/test-cmd`
  is untouched — only a newly generated candidate carries the prefix and requires a fresh Gate 2b
  approval), and which parts of this fix are enforced by an executable assertion versus documented
  as an instruction (no Tuist install in this repo or its CI).

Out of scope:
- Retroactively correcting or invalidating `tests_after` figures already recorded in past run
  reports. The issue's own "Retroactive effect" section flags this as informational only — no
  code artifact to build.
- Migrating already-trusted `.claude/test-cmd` files on existing Tuist projects to the new prefix
  form. Trust is per-SHA (ADR-0014/0020); an existing trusted command is left untouched by
  `detect-test-cmd.sh`'s "already present" short-circuit (unchanged by this fix), and picking up
  the regeneration prefix happens the next time that project's candidate is regenerated from
  scratch and re-approved.
- Any change to `xcodebuild` itself, to Tuist, or to `git-repo-init`'s existing `.gitignore`
  authoring of `*.xcodeproj` (that authoring is correct on its own, per the issue).

## Stack

Bash 3.2-clean shell script (existing constraint on `detect-test-cmd.sh`, unchanged). No new
runtime dependency is introduced; `tuist` is an optional tool the fix must detect the *absence* of
correctly, not one this fix requires installing.

## Architecture

`detect-test-cmd.sh`'s stack-detection `if`/`elif` chain gains one new branch, ordered before the
existing `*.xcodeproj` branch:

1. **New — Tuist-managed project.** Tracked-manifest glob (`Project.swift` or `Tuist.swift` at
   root, or `project.yml` at root) → `STACK="xcode-project-generated"`, `CMD="tuist generate &&
   xcodebuild test -project \"<derived-project>\" -scheme \"<derived-scheme>\" -destination
   '...' -derivedDataPath \"$PWD/.build/DerivedData\""`. The `-project`/`-scheme` values cannot be
   derived from the manifest alone before generation runs; state in the ADR how the candidate
   command derives them (e.g. a fixed convention documented by `git-repo-init`, or a second `tuist
   generate --no-open` dry pass to discover the produced `.xcodeproj` name at candidate-write
   time, never at test-run time).
2. **Unchanged — tracked `.xcworkspace` / hand-maintained `.xcodeproj`.** Existing branches,
   unmodified, now reached only when branch 1 does not match.
3. **Fixed — `swift-package` branch.** `[ -f "Package.swift" ]` becomes `[ -f "Package.swift" ] ||
   [ -f "Tuist/Package.swift" ]`, closing the worktree-visibility gap. Only a detection fix — it
   does not change `CMD="swift test"` for that branch, since a `Tuist/Package.swift` project does
   not need `tuist generate` for a plain `swift test` invocation the way an Xcode-project scheme
   does.

Consumers unaffected by name: `stop-gate.sh`'s existing `CMD=$(awk …)` read of the first
non-comment, non-blank line of `.claude/test-cmd` is unchanged — it runs whatever line
`detect-test-cmd.sh` wrote, including the new `&&`-chained regeneration prefix, exactly as it runs
today's single-command lines.

## Data model / state

No persistent data model. The fields touched are:
- `.claude/test-cmd` — one line, now optionally carrying a `tuist generate &&` prefix ahead of
  the `xcodebuild test` invocation for a detected Tuist stack.
- The chain manifest's `test_cmd_candidate` / TOFU trust registry (`~/.claude/state/stop-gate/trust`)
  — unchanged in shape; a regenerated candidate's SHA differs from any prior trusted SHA for the
  same project, which is what forces a fresh Gate 2b approval (existing mechanism, no schema
  change).

## API / exit-code contract

`detect-test-cmd.sh` itself: no interface change (still `--root <dir> [--dry-run]`, still exit 0
on success / exit 2 on bad invocation, unchanged).

The **generated command's own exit-code contract** is new surface this fix defines:
- Regeneration tool present, `tuist generate` and `xcodebuild test` both run → ordinary pass/fail
  exit code from `xcodebuild`, unchanged from today.
- Regeneration tool (`tuist`) absent from `PATH` at run time → the command must exit a value that
  is neither `0` nor an ordinary `xcodebuild` failure code, and that value must be documented in
  the ADR as the project's DID-NOT-RUN convention for a generated-project test-cmd, consistent
  with this repository's existing rule 4 ("did not run" is not "found nothing").

## UI flows

None — this is a shell-script and chain-documentation fix with no interactive surface beyond the
existing HITL gates (Gate 2 architect review, Gate 2b TOFU approval) already defined by
`concept-to-code`.

## Edge cases

- A project with a tracked (non-gitignored) `.xcodeproj` and no Tuist manifest at all: must
  continue to be detected exactly as today (fallback branch, unchanged `CMD`, no regeneration
  prefix — nothing to regenerate).
- A project with BOTH a Tuist manifest and a `Tuist/Package.swift`: the Tuist-manifest branch
  (new, first) wins — an `xcodebuild test` regeneration path, not a `swift test` one — since the
  project is Xcode-project-shaped, not a plain SwiftPM library.
- `tuist` present in `PATH` at candidate-generation time but later removed before test-cmd
  actually runs (e.g. a different worktree/machine): the DID-NOT-RUN contract applies at *run*
  time, independent of what was true when the candidate was written.
- An existing, already-trusted `.claude/test-cmd` on a Tuist project predating this fix: left
  untouched (existing "already present" short-circuit) — no forced re-approval, no forced
  regeneration prefix, consistent with how ADR-0159's `-derivedDataPath` addition was rolled out.
- A worktree forked with `baseRef: head` for a Tuist-managed project: after this fix,
  `detect-test-cmd.sh`'s Tuist-manifest check finds `Project.swift`/`Tuist.swift`/`project.yml`
  (tracked, so present in every worktree) even though `.xcodeproj` and `.claude/test-cmd` are
  gitignored and absent from that worktree — the worktree still needs its OWN copy of a trusted
  `.claude/test-cmd` to actually run tests, which is an existing, separate concern of how the
  chain propagates trust into a worktree, unchanged by this fix.

## Success criteria

- [ ] R-01 — `detect-test-cmd.sh` detects a Tuist-managed project via a tracked manifest
      (`Project.swift`, `Tuist.swift`, or `project.yml`) before falling back to the existing
      `*.xcodeproj` glob, and this ordering is covered by a fixture-based test with no real Tuist
      install required.
- [ ] R-02 — for a detected Tuist-managed project, the candidate command written to
      `.claude/test-cmd` includes a `tuist generate &&` regeneration prefix ahead of the
      `xcodebuild test` invocation.
- [ ] R-03 — the existing `*.xcodeproj` / `.xcworkspace` detection branches are unmodified in
      behavior for a project with no Tuist manifest present (regression check).
- [ ] R-04 — the `swift-package` branch's `Package.swift` check also matches `Tuist/Package.swift`,
      closing the worktree-visibility gap named in the issue.
- [ ] R-05 — the generated Tuist test-cmd's DID-NOT-RUN exit-code convention (regeneration tool
      absent from `PATH` at run time) is documented in the ADR and is distinguishable, in that
      documentation, from both a clean pass and an ordinary `xcodebuild` test failure.
- [ ] R-06 — an existing, already-trusted `.claude/test-cmd` on a Tuist project is left untouched
      by `detect-test-cmd.sh` (no forced rewrite, no forced re-approval) — regression check against
      the script's current "already present" short-circuit.
- [ ] R-07 — the ADR states which parts of this fix are pinned by an executed fixture-based assertion versus documented as instruction only (no-test: this repository has no Tuist project or Tuist binary to execute a real regeneration against).
      The ADR must name that this repository has no Tuist install in CI or locally, so the actual
      `tuist generate` regeneration step cannot itself be pinned by an executed assertion end to
      end — only detection and prefix generation are.
- [ ] R-08 — the fix does not modify `git-repo-init`'s `.gitignore` authoring of `*.xcodeproj`, `xcodebuild` itself, or Tuist (no-test: explicitly out of scope, nothing to assert against).
