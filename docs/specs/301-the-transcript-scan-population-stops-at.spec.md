# SPEC — the transcript-scan population stops at two roots

Source: GitHub issue #301

## Objectives
1. Re-derive, over the whole of `staging/`, every file that could read a subagent transcript, and
   confirm today's count of readers that sit outside the two roots the class guard currently sweeps
   (`staging/plugin/scripts/*.sh` and `staging/plugin/skills/*/scripts/*.sh`).
2. Widen the transcript-scan class guard's population so that every plausible reader location is
   inside it, with a per-root candidate count so a renamed or relocated subtree fails loudly instead
   of silently shrinking the denominator.
3. Keep the known `compliant()` false positive pinned as expected, together with the instruction
   that the remedy is to extend the predicate rather than exempt a hook that in fact complies.

## Scope
In: the derivation, the denominator guard and the `compliant()` predicate inside
`staging/plugin/scripts/tests/transcript-scan-rule.test.sh`; the enumeration of candidate reader
locations under `staging/`; the per-root count guards; the assertion that pins the false positive
and its accompanying instruction.

Out: changing any hook's behaviour. `write-scope-enforce.sh`, `test-write-scope.sh`,
`agent-write-scope.sh` and `pre-flight-pattern-enforce.sh` are not modified by this feature; the
rule itself (read only the FIRST `user` entry, or declare why not) is not restated or relaxed; the
existing `# transcript-scan-exempt:` waiver syntax and its 40-character reason floor are unchanged;
the deployed tree under `~/.claude` is out of scope.

## Stack
Bash 3.2 (macOS-portable) shell scripts under `staging/plugin/scripts/` and
`staging/plugin/skills/*/scripts/`; Markdown SKILL.md instruction files; awk predicates; a 68-file
`*.test.sh` harness under `staging/plugin/scripts/tests/` run by `.claude/test-cmd`; GitHub Actions
CI (`ci`, `markdownlint`, `links`). No application runtime.

## Architecture
- `staging/plugin/scripts/tests/transcript-scan-rule.test.sh` — the class guard. Holds
  `population()` (which since ADR-0085 takes file paths rather than a directory, because the two
  roots sit at different depths), `compliant()`, the `T0a`/`T0b` count guards, the sweep `T1`, the
  compliance assertions `T2`/`T3`, the reason floor `T4`, the no-list-in-the-test assertion `T5`,
  and `Z5` (the `compliant()` false positive, pinned as expected-non-compliant with the
  extend-the-predicate instruction).
- Candidate reader roots to be enumerated: `staging/plugin/scripts/*.sh`,
  `staging/plugin/skills/*/scripts/*.sh`, and the locations ADR-0085 names as outside both globs —
  `staging/user/` and anything under `staging/plugin/` that is not `scripts/`.
- The two enforcing hooks the rule binds: `staging/plugin/scripts/write-scope-enforce.sh` and
  `staging/plugin/scripts/test-write-scope.sh`. The declared-exemption holders:
  `staging/plugin/scripts/pre-flight-pattern-enforce.sh` (exempt on DIRECTION) and the probe-only
  scripts.
- `docs/architecture/ADR-0085-208-derived-guard-boundaries.md` — the source; the quoted disclosure
  is near the end of its Known-consequences section, and the line number cited in the issue will
  have moved.
- `docs/architecture/ADR-0077-193-transcript-scan-class-guard.md` — the rule this guard enforces.
- `staging/plugin/scripts/tests/plant-check.sh` — the plant registry that must carry a declared
  plant for each new assertion.
- `.github/workflows/ci.yml` and `.github/workflows/docs-ci.yml` — the harness runners.

## Data model
None. The only structured artifact is the existing one-line source marker
`# transcript-scan-exempt: <reason>` and, new to this feature, a per-root candidate count used by
the denominator guard.

## API / Interfaces
- `population <file>...` — takes file paths, returns those that reference a transcript at all
  (`transcript_path` or `.jsonl`). Signature preserved; the caller's file list widens.
- `compliant <file>` — returns whether the first pipe stage after the `jq` read of `user` entries is
  `head -1`. Its known false positive (a rule-abiding non-`jq` reader is reported non-compliant)
  stays.
- Per-root candidate counting for the denominator guard, replacing a single aggregate `N >= 8`
  threshold that the hooks alone can satisfy.

## UI flows
None. The feature is a test-harness guard; it surfaces only as `PASS`/`FAIL` lines in the CI run.

## Edge cases
- Zero matches is the correct, expected state (ADR-0085 measured 0 of 38 skill scripts reading a
  transcript). Zero candidates is a broken derivation. The two are indistinguishable from outside
  unless the guard sits on the denominator.
- A single aggregate count is satisfied by one root alone, so a renamed or emptied second root
  leaves that root uncovered while the count stays green.
- A reader that is genuinely non-`jq` (for example a `python3` reader) trips `compliant()`'s false
  positive. Per R-02 the response is to extend the predicate, never to add an exemption — an
  exemption there would record the opposite of the truth for every later reader.
- A file added under a root that neither glob resolves is outside the population and outside the
  denominator guard at once.
- Per the repository's standing rules: this guard is a checker, so a "did not run" state must stay
  distinguishable from "found nothing", and any new assertion must be seen RED against a declared
  plant in `plant-check.sh`.

## Success criteria
- [ ] R-01 — the population covers every plausible reader location, with a per-root candidate count
      so a renamed subtree fails loudly rather than shrinking the denominator in silence.
- [ ] R-02 — `compliant()`'s known false positive stays pinned as expected, and the instruction that
      the fix is to extend the predicate rather than exempt a compliant hook survives.
