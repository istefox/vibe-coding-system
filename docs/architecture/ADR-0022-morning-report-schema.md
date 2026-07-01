# ADR-0022 — Morning report schema v2.0

**Companion to:** ADR-0022 (D9)
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
  "schema": "2.0",
  "run_id": "<string, e.g. the launch timestamp or roadmap name>",
  "project_root": "<abs path>",
  "status": "success | partial | aborted",
  "abort_reason": "<string or null>",
  "started_at": "<ISO-8601>",
  "ended_at": "<ISO-8601>",
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
      "guard_halt": "<reason or null>"
    }
  ],
  "guard_halts": [
    { "feature": "<slug>", "reason": "<halt reason from nightly-guard>" }
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

---

## Relationship to v1.0

v1.0 (`autopilot-report.json`) is single-feature, local-commit-only, and has no publish or CI fields.
v2.0 adds the `features[]` array, the per-feature `pr_url` / `ci_status` / `guard_halt`, the
`guard_halts[]` roll-up, and `spend`. A v1.0 reader ignores the new fields; a v2.0 reader treats a
missing `features[]` as a single-feature v1.0 report.
