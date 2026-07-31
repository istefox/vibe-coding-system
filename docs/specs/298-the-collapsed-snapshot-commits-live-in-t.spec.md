# SPEC — the collapsed snapshot commits live in the reflog only and a git gc destroys them

Source: GitHub issue #298

## Objectives

1. Establish what is actually unrecoverable after `git gc --prune=now` following a Step 7 collapse,
   and what a human would need in order to inspect intermediate stage output.
2. Either record the pre-collapse tip durably as an additive manifest field with no schema bump, or
   state positively in the ADR that it is not needed and why.
3. Leave the four existing refusal guards untouched and still isolating independently.

## Scope

In: the residual of ADR-0104's Step 7.0 soft reset — where the pre-collapse tip is recorded, and
whether anything genuinely needs the intermediate stage commits once Step 5 is over. The decision
must be made before deciding where to record anything.

Out: the collapse itself and its rationale (ADR-0104: the snapshots exist so the next stage can fork
and Step 5 is over). The four refusal guards' logic. The merge-back protocol and the snapshot commit
message format, which `SC8` pins as a cross-file contract.

## Stack

Bash 3.2 (macOS-portable) shell scripts under `staging/plugin/scripts/` and
`staging/plugin/skills/*/scripts/`; Markdown SKILL.md instruction files; awk predicates; a 68-file
`*.test.sh` harness under `staging/plugin/scripts/tests/` run by `.claude/test-cmd`; GitHub Actions
CI (`ci`, `markdownlint`, `links`). No application runtime.

## Architecture

- `staging/plugin/skills/concept-to-code/SKILL.md` — Step 7.0, the declared collapse fence. It reads
  `recovery_baseline_sha`, applies four guarded refusals in order (`noBaseline` /
  `baselineGone`, `notAncestor`, `noCommits`, `foreignCommit`), performs `git reset --soft`, and
  emits `COLLAPSED <n> <sha>`, `COLLAPSE_SKIP <reason>` or `COLLAPSE_NOREPO` with exit 3. The block
  below interprets each token. Line numbers will have moved.
- `staging/plugin/skills/concept-to-code/scripts/manifest-init.sh` — where an additive field would
  be added, on the same terms as `step5_mode`, `hook_verified` and `step5_review_mode` (no schema
  version bump).
- `staging/plugin/skills/concept-to-code/scripts/manifest-validate.sh` and
  `manifest-field-state.sh` — any new field must follow ADR-0076's rule: `ABSENT` is a distinct
  state from `INVALID` and from `UNREADABLE`, read through the helper, never with a bare `m.get()`.
- `staging/plugin/scripts/tests/step7-snapshot-collapse.test.sh` — the harness file executing this
  fence, including the fixture whose chain-shaped commit message isolates the ancestry guard from
  the foreign-commit guard.
- `staging/plugin/scripts/tests/plant-check.sh` — the plant registry runner (ADR-0108).
- `docs/architecture/ADR-0104-249-step7-snapshot-collapse.md` — the source, whose quoted line number
  will have moved, and which records the plant that did not fire because two guards covered the same
  fixture; and `docs/architecture/ADR-0103-244-recovery-baseline-rebase.md`, since `notAncestor` is
  #244's state, refused here rather than inherited.

## Data model

Candidate additive manifest field: the pre-collapse tip sha, written at Step 7.0 before the soft
reset. If added it must be additive, absent-tolerant per ADR-0076, and carry a decided meaning for
each of the collapse outcomes (`COLLAPSED`, each `COLLAPSE_SKIP` reason, `COLLAPSE_NOREPO`).

If the decision is that nothing needs it, the deliverable is the positive statement in the ADR
rather than a field. `TBD` until the measurement in R-01's first half is done.

## API / Interfaces

The Step 7.0 fence: stdout token plus exit status, consumed by the Step 7 block that then invokes
the `commit` skill. If a field is added, `manifest-field-state.sh` is the read interface and
`manifest-init.sh` the write interface.

## UI flows

None.

## Edge cases

- `git gc --prune=now` immediately after a collapse — the case the issue names.
- A reflog whose default expiry has been shortened by configuration, which is the same case
  arriving by a different route.
- Each of the four refusal outcomes, where no reset happens and there is no pre-collapse tip
  distinct from `HEAD`.
- `COLLAPSE_NOREPO` (exit 3), which must stay distinguishable from a legitimate skip.
- A resumed or paused Step 5 whose baseline is orphaned (#244's state) — the `notAncestor` guard
  refuses, and a new field must not record something misleading there.
- Two guards covering the same fixture: ADR-0104 records a plant that did not fire for exactly this
  reason, so R-02's "still isolate independently" needs each guard exercised by a fixture only it
  can refuse.
- Per the standing rules in the issue footer, both directions per contract, and every new assertion
  seen RED against a declared plant.

## Success criteria

- [ ] R-01 — either the pre-collapse tip is recorded durably (a manifest field, additive, no schema
      bump) or the ADR states positively that it is not needed and why.
- [ ] R-02 — the four existing refusal guards are untouched and still isolate independently;
      ADR-0104 records a plant that did not fire because two guards covered the same fixture.
