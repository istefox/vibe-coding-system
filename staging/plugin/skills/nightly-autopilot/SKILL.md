---
name: nightly-autopilot
description: >
  Overnight autonomous roadmap-to-PR runner (ADR-0022). Given a target repo with an
  opt-in marker, a PROJECT.md roadmap, and TOFU-trusted tests, it drives project-conductor
  in roadmap-autopilot mode: each feature is implemented, reviewed, committed on feat/*,
  pushed, and opened as a PR to main with CI green. Never merges, never force-pushes, never
  touches main. A nightly-guard hook halts on real trouble and leaves a morning report.
  Set with /goal as the outer keep-alive loop and a non-blocking permission mode.
---

# `nightly-autopilot` — Overnight Roadmap-to-PR Runner

Runs an already-designed roadmap unattended and delivers PR-ready branches by morning. The human
approves SPEC/ADR/plan in the evening (still HITL), sets `/goal` plus a non-blocking permission mode,
launches this skill, and walks away. Nothing is merged to `main`.

**Architecture reference:** ADR-0022. Report schema: `ADR-0022-morning-report-schema.md`.

Relationship to the rest of the stack: this skill owns launch, publish, guard wiring, CI setup, and
the morning report. It delegates the per-feature roadmap loop to `project-conductor` (roadmap-autopilot
mode), which reuses `concept-to-code` autopilot / `autopilot-build` for the implement-review-commit
mechanics unchanged.

---

## 1. When to invoke

```
/skill nightly-autopilot
```

Project root = `$PWD`. Run this only after the evening design gate is done: SPEC/ADR/plan approved for
each roadmap feature, or a roadmap of features whose chains will run in autopilot.

**Launch order (see `docs/RUNBOOK-nightly-autopilot.md`):**
1. Set a non-blocking permission mode (`acceptEdits` or bypass) so no per-tool prompt fires.
2. Set the outer loop: paste the `/goal` template this skill prints (Phase 1).
3. Invoke this skill.

`/goal` is the outer keep-alive; this skill runs with or without it, but without `/goal` the session
will not re-enter after a turn ends.

---

## 1.5 Phase P — Prep: auto-generate the design inputs (ADR-0023)

Runs before pre-flight, and only when the opt-in marker declares a prep source. Idempotent: each
step skips whatever already exists. With no `prep:` block the phase is a no-op and the run behaves
exactly as ADR-0022 (roadmap and specs must pre-exist).

Read the source from `.claude/nightly-autopilot.yml`:
```yaml
publish: true
prep:
  source: issues
  issues_label: release-blocker
```

Steps (each is skip-if-present):

1. **test-cmd file** — if `.claude/test-cmd` is absent, run
   `~/.claude/hooks/detect-test-cmd.sh --root "$PWD"` to write a candidate from stack detection.
   This writes the FILE only; it never grants trust (that stays human, D3).
2. **Roadmap** — if `PROJECT.md` is absent, run
   `~/.claude/hooks/roadmap-from-issues.sh --root "$PWD" --label "<issues_label>"` to build
   `PROJECT.md` (one feature per issue) and `docs/specs/_issue-map.tsv`.
3. **Per-feature SPEC** — for each row in `docs/specs/_issue-map.tsv` whose
   `docs/specs/<slug>.spec.md` is absent, invoke `Skill(spec-from-issue, "<issue#> --slug <slug>")`.
   A thin or vague issue is SKIPPED (marked `[~]` in PROJECT.md with a `needs-human` note), never
   fabricated.

Record for the report (schema v2.1 `prep` block): `features_generated`, `features_skipped_thin`,
`test_cmd_created`. Then fall into Phase 0. Phase 0 still enforces the TOFU-trust and gh-auth wall;
Phase P grants neither.

---

## 2. Phase 0 — Hard pre-flight (read-only, script-level)

Any failure writes an `aborted` report and stops. No dispatch, no push. Emit one line per check.

1. **Scope guard (first):** resolve `$PWD`. Every downstream action is scoped to it. If a later
   manifest names a `project_root` outside `$PWD`, abort (same rule as autopilot-build check 1).
2. **Git repo:** `git rev-parse --git-dir` succeeds.
3. **Opt-in marker:** `.claude/nightly-autopilot.yml` exists and sets `publish: true`. Absent or
   `false` → abort with "publish not opted-in for this repo; run stops at local commit, use
   autopilot-build instead."
   ```bash
   m="$PWD/.claude/nightly-autopilot.yml"
   test -f "$m" || { echo "✗ opt-in: $m missing"; exit 1; }
   grep -qE '^[[:space:]]*publish:[[:space:]]*true[[:space:]]*$' "$m" || { echo "✗ opt-in: publish not true"; exit 1; }
   ```
4. **PROJECT.md present:** `test -f PROJECT.md`. Phase P generates it from issues; if it is still
   absent (no prep source and none pre-existing) → abort ("no roadmap; add a `prep.issues_label` to
   the opt-in marker or create PROJECT.md").
5. **TOFU test-cmd trusted:** `.claude/test-cmd` is not `NONE`/placeholder and its SHA-pinned
   `(hash, normalized-root)` pair is in `~/.claude/state/stop-gate/trust` (same check as
   autopilot-build check 6). Never auto-grant. Phase P may have written the `.claude/test-cmd`
   file, but trust is still human: if untrusted, abort with the exact one-liner,
   "test-cmd not trusted — review `.claude/test-cmd` then run once:
   `bash ~/.claude/hooks/approve-test-cmd.sh \"$PWD\"`".
6. **hook_verified known (roadmap-wide, pre-flight):**
   ```bash
   _manifests=$(ls "$PWD"/docs/manifests/*.manifest.yml 2>/dev/null)
   if [ -z "$_manifests" ]; then
     echo "note: no manifests exist yet (Phase P has not created any feature manifest). Each"
     echo "feature's manifest defaults hook_verified: false (safe Agent-tool fallback dispatch,"
     echo "ADR-0016) at manifest-init.sh creation time, so there is nothing to validate yet and"
     echo "this is not an abort condition. No global cross-run smoke-test record exists"
     echo "(ADR-0029 Section 1, 'Gap flagged for issue #34') -- hook-verify-workflow.sh is"
     echo "deliberately read-only and stateless; this check does not depend on one existing."
   else
     _bad=0
     for _m in $_manifests; do
       _hv=$(python3 -c "import yaml; m=yaml.safe_load(open('$_m')); print(m.get('hook_verified'))" 2>/dev/null)
       if [ "$_hv" != "True" ] && [ "$_hv" != "False" ]; then
         echo "✗ hook_verified: $_m has hook_verified=$_hv (must be true/false). Manifest is corrupted or was hand-edited; fix or re-init."
         _bad=1
       fi
     done
     [ "$_bad" -eq 0 ] || exit 1
   fi
   ```
   (drives Workflow vs Agent-tool dispatch downstream, per manifest, exactly as before.)
7. **`gh` authenticated:** `gh auth status` succeeds (needed to push and open PRs).
8. **CI + branch protection:** if `.github/workflows/ci.yml` is absent, drop the template
   (`~/.claude/templates/ci.yml` at runtime; source `staging/project-templates/ci/ci.yml`),
   substituting `__TEST_CMD__` with the trusted `.claude/test-cmd`, then run
   `~/.claude/hooks/set-branch-protection.sh`. If present, verify the `ci` check is required on
   `main`.

On all checks passing:
```
nightly-autopilot · pre-flight PASSED · arming guard, starting roadmap...
```

No `AskUserQuestion` is called after this point.

**Permission posture (ADR-0020 CC 2.1.186 note).** An unattended dispatch is only safe when the
Step-5 allowlist covers every tool the subagents use; an out-of-allowlist tool raises a prompt that
stalls the run. Keep hooks enabled or `/goal` cannot evaluate and the guard cannot fire.

---

## 3. Phase 1 — Arm and drive the roadmap

### 3.1 Arm the nightly state

```bash
mkdir -p "$PWD/.claude/nightly-state"
touch "$PWD/.claude/nightly-state/active"          # activates nightly-guard for this repo
: > "$PWD/.claude/nightly-state/build-status"      # cleared; set GREEN/RED after each test run
```

Record `started_at` via `date -u +%Y-%m-%dT%H:%M:%SZ`.

### 3.2 Print the `/goal` template

Print this for the human to paste (it keys off the status line the publish step prints, since the
`/goal` evaluator cannot call tools):

```
/goal "Every feature in PROJECT.md is [x], committed on feat/*, pushed, and a PR is open,
as shown by a NIGHTLY-PUBLISH line for each feature and no NIGHTLY-GUARD HALT line.
Or stop after <N> turns."
```

### 3.3 Drive project-conductor in roadmap-autopilot

Invoke `Skill(project-conductor, "nightly")`. The conductor (roadmap-autopilot mode) pre-authorizes
every pending feature, skips the per-feature Step 3 gate, and for each feature:
implement → review-triage-fix → local commit → `publish-feature.sh` (guard fires) → print the
`NIGHTLY-PUBLISH` status line → advance to the next `[ ]`.

Marker contract (read by `nightly-guard`): the conductor writes `build-status` GREEN before each
publish and, on a feature that fails to reach `completed`, writes a run-level `needs-human` marker.
`rtf-blocker` is written by the review step (ADR-0020 scope) when review-triage-fix raises a BLOCKER.
`token-budget` is written by this skill from the `/goal` overlay.

A Step 5 anti-test-weakening halt (ADR-0047 §D5) means the feature never reaches `completed`, so
the conductor writes the run-level `needs-human` marker exactly as it does for any other feature
that fails to complete, and the guard blocks that publish and every subsequent one. The reason is
recorded in `guard_halts[]` in the morning report. This skill runs no scan of its own — detection
happens once, inside `concept-to-code` Step 5, and this skill only surfaces the resulting halt.

The halt markers (`needs-human`, `rtf-blocker`, `token-budget`) are run-level: once any is set, the
guard blocks every subsequent publish, so a HALT stops the whole roadmap rather than skipping one
feature. A halted feature keeps its local commit but has no ready PR.

---

## 4. Phase 2 — Morning report and disarm

On every exit path, write `<project_root>/.claude/nightly-report.json` (schema v2.1: v2.0 fields plus
the Phase P `prep` block) with per-feature
`status`, `branch`, `commit_sha`, `pr_url`, `ci_status`, `guard_halt`, the `guard_halts[]` roll-up,
and `spend` (from the `/goal` overlay). Set `ended_at` via `date -u`.

Disarm the guard:
```bash
rm -f "$PWD/.claude/nightly-state/active"
```

Emit one terminal line:
```
nightly-autopilot · <status> · report: <project_root>/.claude/nightly-report.json
```

Reconcile CI where possible: for each open PR, `gh pr checks <url>` maps the check to
`green|red|pending` in the report.

---

## 5. Safety invariants

- **No merge, ever.** No code path calls `gh pr merge`, `--merge`, or enables auto-merge.
- **No force-push, no main.** Publish targets `feat/<slug>` only; the settings deny list blocks
  force-push; `publish-feature.sh` refuses a slug that resolves to `main`/`master`.
- **Why "no merge" is load-bearing, not a convenience (ADR-0059 §D2).** Phase P (§1.5) can turn a
  GitHub issue body into this run's design input, and an issue body is attacker-controllable text.
  Prompt fencing and the injection scan (ADR-0059 §D1/§D3) are a mitigation, not a boundary — the
  mechanism reading that text is the same mechanism an attacker is trying to redirect. The actual
  boundary is that this path cannot merge, force-push, or write `main`; a pushed branch and an open
  PR are reversible, and the human reviews before either stops being true. **Granting merge
  authority to this path would turn every issue body into a remote code execution vector**: a
  malicious issue could get its own code merged to `main` overnight with no human in the loop,
  using this skill's own commit-and-push privileges to do it. Do not add merge authority here
  without addressing that first.
- **Opt-in per repo.** Absent or `publish: false` marker → the skill never pushes; use
  `autopilot-build` for a local-commit-only run.
- **Guard fails safe.** On any halt condition or internal guard error, the publish is blocked and the
  PR is left not-ready. Nothing broken looks mergeable.
- **Hooks stay active.** `stop-gate.sh`, `pre-flight-pattern-enforce.sh`, `protect-files.sh`,
  `db-backup-guardrail.sh`, and `nightly-guard.sh` all fire. Autopilot suppresses human prompts, not
  safety mechanisms.
- **TOFU never auto-granted.** Pre-flight reads the trust file; it never writes it.

---

## 6. Out of scope (v1)

- Auto-merge on green — rejected in ADR-0022 (Alt A); the morning merge is the human checkpoint.
- Cron scheduling (`CronCreate`) — wrap once the Phase 4 smoke test passes.
- CI reconciliation beyond a single `gh pr checks` pass — a watcher that waits for CI to finish is
  deferred; the report records `pending` if CI has not settled.
