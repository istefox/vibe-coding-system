# ADR-0022 — Morning report schema (v2.2)

**Companion to:** ADR-0022 (D9); v2.1 `prep` block added by ADR-0023; v2.2 `features_skipped[]`
added by ADR-0060 (§D3/§D5, issue #114)
**Extends:** `autopilot-report.json` v1.0 (ADR-0020 D7)

The overnight run writes one run-level report at `<project_root>/.claude/nightly-report.json` on
every exit path (success, partial, aborted). It aggregates the per-feature results of a roadmap. Each
feature may still produce its own v1.0 `autopilot-report.json` from `autopilot-build`; the nightly
report is the roll-up a human reads in the morning.

`started_at` and `ended_at` come from `date -u +%Y-%m-%dT%H:%M:%SZ` (scripts cannot call
`Date.now()`). `spend` is populated from the `/goal` overlay figures surfaced in the session.

---

## Schema

```json
{
  "schema": "2.2",
  "run_id": "<string, e.g. the launch timestamp or roadmap name>",
  "project_root": "<abs path>",
  "status": "success | partial | aborted",
  "abort_reason": "<string or null>",
  "started_at": "<ISO-8601>",
  "ended_at": "<ISO-8601>",
  "prep": {
    "source": "issues | null",
    "issues_label": "<label or null>",
    "features_generated": 0,
    "features_skipped_thin": [ { "issue": 0, "reason": "<thin-issue reason>" } ],
    "test_cmd_created": false
  },
  "features": [
    {
      "feature": "<roadmap line text>",
      "slug": "<kebab slug>",
      "status": "success | partial | halted | skipped",
      "branch": "feat/<slug>",
      "commit_sha": "<sha or null>",
      "test_result": "GREEN | RED | NOT_RUN",
      "pr_url": "<url or null>",
      "ci_status": "green | pending | red | unknown",
      "guard_halt": "<reason or null>",
      "test_count_delta": 4,
      "deleted_lines": 37,
      "iteration_count": 11,
      "elapsed_wall_seconds": 942
    }
  ],
  "guard_halts": [
    { "feature": "<slug>", "reason": "<halt reason from nightly-guard>" }
  ],
  "features_skipped": [
    { "feature": "<slug or issue reference>", "reason": "<skip reason>" }
  ],
  "spend": { "tokens": 0, "turns": 0, "wall_seconds": 0 },
  "features_done": 0,
  "features_failed": 0,
  "next_action": "<human-facing instruction>"
}
```

### Field notes

- `status` (run-level): `success` only when every pending feature reached `success`; `partial` when
  at least one feature halted or failed but others completed; `aborted` when pre-flight failed and no
  feature ran.
- `features[].status`: `halted` means the guard stopped the publish; the branch may be pushed but no
  ready PR exists. `partial` means implementation or tests did not complete.
- `pr_url` is null on any feature that did not reach a clean publish. A halted feature never carries a
  ready `pr_url`.
- `ci_status` starts `pending` at publish time; a later pass may reconcile it to `green` or `red` from
  `gh pr checks`. `unknown` when CI could not be queried.
- `next_action` is the one-line morning instruction, for example: "Review N open PRs and merge the
  green ones" or "Feature <slug> halted: <reason>. Resume interactively."
- `test_count_delta`, `deleted_lines`, `iteration_count`, `elapsed_wall_seconds` (ADR-0064, issue
  #118) are additive, conditional-if-present, **no schema bump**: summed from that feature's own
  `task_metrics` array in its `step5-report.json`, when that file carries one. These are METRICS,
  not findings (ADR-0064 §D2) — no morning-report reader branches on them, and they are absent
  entirely (not `0`) on any feature whose `step5-report.json` predates this feature or carries no
  `task_metrics` (ADR-0064 §D3 — absent means not recorded, never zero, applied here exactly as it
  is applied in `step5-report.json` itself).
- `features_skipped[]` (v2.2, ADR-0060) is read from `<project_root>/.claude/nightly-state/skipped-
  features`, one entry per line. It is **not** the same thing as `guard_halts[]`: a halt stopped
  the whole roadmap, a skip did not — the feature it names simply never started, and every other
  pending feature ran normally. `prep.features_skipped_thin[]` (v2.1) and `features_skipped[]`
  (v2.2) can both be non-empty for the same run: the former is populated during Phase P from the
  same underlying file, before any per-feature chain has started; the latter is the run-level
  roll-up taken at the same point Phase 2 reads everything else. Neither implies the other is
  empty.

---

## Relationship to v1.0

v1.0 (`autopilot-report.json`) is single-feature, local-commit-only, and has no publish or CI fields.
v2.2 adds `features_skipped[]` (ADR-0060 §D3/§D5, issue #114): the per-feature skip roll-up, read
from `.claude/nightly-state/skipped-features` and kept separate from `guard_halts[]` on purpose — a
skip did not stop the roadmap, a halt did. v2.1 adds the `prep` block (ADR-0023: `source`,
`issues_label`, `features_generated`, `features_skipped_thin[]`, `test_cmd_created`); a run with no
prep source leaves it null. v2.0 adds the `features[]` array, the per-feature `pr_url` /
`ci_status` / `guard_halt`, the `guard_halts[]` roll-up, and `spend`. A v1.0 reader ignores the new
fields; a v2.0 reader treats a missing `features[]` as a single-feature v1.0 report; a pre-v2.2
reader treats a missing `features_skipped[]` as "nothing to add" (additive, empty-list-equivalent).
