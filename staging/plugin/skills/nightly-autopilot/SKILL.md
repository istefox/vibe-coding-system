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
1. Set **`bypassPermissions`**. It is the only mode under which no per-tool prompt can fire, and
   an overnight run is exactly the case that needs that.
   **`acceptEdits` is NOT equivalent and the difference is not cosmetic** (issue #339): it
   auto-accepts *edits*, while a Bash command outside `permissions.allow` still prompts — and the
   chain's Bash surface (`bash ~/.claude/skills/*/scripts/manifest-*.sh`, `sed`, `awk`, `mkdir`,
   `git push`, `gh pr create`, the project's own test-cmd) is not in a default allowlist. Choose
   `acceptEdits` only if you have checked that yours covers all of it.
   **Three ways to set it, and `/permissions` is not one of them** — that command manages
   allow/ask/deny rules, and hooks are a third axis it does not touch either:
   - **Shift+Tab** cycles `default → acceptEdits → plan → bypassPermissions → auto → default`.
     Read the mode off the status line rather than counting presses.
   - `claude --permission-mode bypassPermissions` at launch.
   - `permissions.defaultMode` in `~/.claude/settings.json` for the durable default.

   The safety layer does not go away with the prompts: `stop-gate`, `pre-flight-pattern-enforce`,
   `protect-files`, `db-backup-guardrail`, `write-scope-enforce`, `agent-write-scope`,
   `agent-command-scope` and `nightly-guard` all still fire, and a hook deny overrides any
   permission mode. That is the design ADR-0022 states: autopilot bypasses the human-decision
   layer, never the safety layer.
2. Set the outer loop: paste the `/goal` template this skill prints (Phase 1).
3. Invoke this skill.

`/goal` is the outer keep-alive; this skill runs with or without it, but without `/goal` the session
will not re-enter after a turn ends.

---

## 1.4 Phase M — Permission posture (issue #320, ADR-0110)

**Runs FIRST, before Phase P.** Phase P writes `.claude/test-cmd`, `PROJECT.md` and per-feature
SPECs; a blocking mode stalls all of that before Phase 0 would ever get a turn, which is the same
silent-and-late failure this check exists to close, one phase up.

Item 1 of the launch order above was stated in prose three times in this file and **verified
nowhere**. On 2026-07-31 pre-flight printed `PASSED`, the guard armed, the roadmap started, and the
chain died at its first Gate 0 write with nobody present to answer the prompt. Every other
precondition fails loudly and early; this one is also the only one whose failure is *guaranteed*
fatal rather than conditional.

<!-- fence-contract: nightly-permission-posture -->
```bash
_pms=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/permission-mode-state.sh" ]; then
  _pms="$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/permission-mode-state.sh"
elif [ -f "$HOME/.claude/skills/concept-to-code/scripts/permission-mode-state.sh" ]; then
  _pms="$HOME/.claude/skills/concept-to-code/scripts/permission-mode-state.sh"
else
  echo "✗ permission posture: permission-mode-state.sh not found — the check DID NOT RUN."
  echo "  Run: bash <repo>/staging/sync-to-claude.sh --apply"
  exit 1
fi
_pm=$(bash "$_pms" 2>&1); _pmrc=$?
if [ "$_pmrc" -eq 3 ]; then
  echo "✗ permission posture: the check DID NOT RUN — $_pm"
  echo "  An unrun check is not a clean result. Fix the environment and relaunch."
  exit 1
fi
[ "$_pmrc" -eq 0 ] || { echo "✗ permission posture: bad invocation — $_pm"; exit 1; }
_pmtok="${_pm%%|*}"; _pmval="${_pm#*|}"
case "$_pmtok" in
  NONBLOCKING)
    # The two NONBLOCKING modes get DIFFERENT sentences, because they are not the same guarantee
    # (issue #339). Promising acceptEdits that nothing can interrupt it is false whenever a Bash
    # command falls outside permissions.allow, and this is the operator-facing line that decides
    # whether someone walks away from the machine. This comment deliberately does not quote the
    # old wording: a guard bans that phrase where it is unqualified, and a scan whose needle is a
    # literal counts its own explanation (rule 12).
    if [ "$_pmval" = "bypassPermissions" ]; then
      echo "✓ permission posture: bypassPermissions — no per-tool prompt can fire."
    else
      echo "✓ permission posture: $_pmval — edits are auto-accepted, but a Bash command outside"
      echo "  permissions.allow STILL PROMPTS, and there is nobody to answer it. Proceeding"
      echo "  because you may have an allowlist that covers this chain's Bash surface; if you"
      echo "  have not checked, stop and relaunch with bypassPermissions."
    fi ;;
  BLOCKING)
    echo "✗ permission posture: this session is in '$_pmval', which can prompt or deny."
    echo "  Nobody is here to answer it, so the run would stall with state half-written."
    echo "  Set a non-blocking mode and relaunch. /permissions does NOT do this — it manages"
    echo "  allow/ask/deny rules. Hooks are a separate axis and stay enabled either way:"
    echo "    launch with: claude --permission-mode bypassPermissions   (the mode to use)"
    echo "    or Shift+Tab through default → acceptEdits → plan → bypassPermissions → auto,"
    echo "    reading the mode off the status line rather than counting presses,"
    echo "    or set permissions.defaultMode in ~/.claude/settings.json."
    echo "  acceptEdits is accepted too, but it only auto-accepts EDITS — Bash outside"
    echo "  permissions.allow still prompts. Use it only with an allowlist you have checked."
    exit 1 ;;
  UNCLASSIFIED)
    echo "✗ permission posture: mode '$_pmval' is UNCLASSIFIED — not known-bad, just unmeasured."
    echo "  Nobody has established whether it prompts, so a pre-flight refuses it rather than"
    echo "  gamble a night on it. Use bypassPermissions, or measure '$_pmval' and add it to"
    echo "  permission-mode-state.sh's enumeration."
    exit 1 ;;
  UNOBSERVABLE)
    echo "✗ permission posture: the effective mode could not be observed — $_pmval"
    echo "  This is a fact about this build, not a bad mode: the transcript field is CC 2.1.220+."
    echo "  Verify the mode by hand before relaunching; this gate fails closed on purpose,"
    echo "  because the alternative is the silent PASSED that cost the 2026-07-31 run."
    exit 1 ;;
  *)
    echo "✗ permission posture: unrecognised token '$_pmtok'"; exit 1 ;;
esac
```

On pass, fall into Phase P.

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
   `docs/specs/<slug>.spec.md` is absent, invoke `Skill(skill="spec-from-issue", args="<issue#> --slug <slug>")`.
   A thin or vague issue is SKIPPED (marked `[~]` in PROJECT.md with a `needs-human` note), never
   fabricated.

Record for the report (schema v2.1 `prep` block): `features_generated`, `features_skipped_thin`,
`test_cmd_created`. Then fall into Phase 0. Phase 0 still enforces the TOFU-trust and gh-auth wall;
Phase P grants neither.

**External-dependency check (G13, ADR-0060) is NOT a Phase P step.** It runs later, per feature,
at that feature's own Gate 2c inside the per-feature chain §3.3 drives — a plan's declared
dependencies do not exist until that feature's architect has run, which is after this phase. It is
named here because a BLOCK there reuses this section's skip vocabulary (mark `[~]`, append a
reason) via the same per-feature `skipped-features` note §3.3 describes, never the run-level
`needs-human` marker.

---

## 2. Phase 0 — Hard pre-flight (read-only, script-level)

Any failure writes an `aborted` report and stops. No dispatch, no push. Emit one line per check.

**The permission posture is NOT one of these eight, and must not be added as a ninth.** It is
checked in Phase M, above Phase P, because Phase P writes files and a blocking mode would stall it
before this section ran at all (ADR-0110). Adding a copy here would be a second answer to "may this
run start" — see `permission-mode-state.sh`'s header for why there is exactly one.

1. **Scope guard (first):** resolve `$PWD`. Every downstream action is scoped to it. If a later
   manifest names a `project_root` outside `$PWD`, abort (same rule as autopilot-build check 1).
2. **Git repo:** `git rev-parse --git-dir` succeeds.
3. **Opt-in marker:** `.claude/nightly-autopilot.yml` exists and sets `publish: true`. Absent or
   `false` → abort with "publish not opted-in for this repo; run stops at local commit, use
   autopilot-build instead."
   <!-- fence-contract: nightly-autopilot-optin -->
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
   <!-- fence-contract: nightly-autopilot-check-6 -->
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
     # The field-state helper. Two-tier resolution, same order project-conductor and commit use.
     # If NEITHER resolves the pre-flight aborts: this is a gate, and an infrastructure gap must
     # fail closed and loudly, never quietly fall back to a second copy of the logic (issue #195).
     if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/manifest-field-state.sh" ]; then
       _mfs="$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/manifest-field-state.sh"
     elif [ -f "$HOME/.claude/skills/concept-to-code/scripts/manifest-field-state.sh" ]; then
       _mfs="$HOME/.claude/skills/concept-to-code/scripts/manifest-field-state.sh"
     else
       echo "✗ hook_verified: manifest-field-state.sh not found in either location."
       echo "  Run: bash <repo>/staging/sync-to-claude.sh --apply"
       exit 1
     fi
     _bad=0
     for _m in $_manifests; do
       # Four states, not two (issue #123, ADR-0075). `m.get('hook_verified')` returned None for a
       # field that is ABSENT and for one explicitly set to null, and an empty string when the file
       # could not be parsed at all — so a manifest older than the field was reported as corrupted,
       # and a manifest the check never read was reported as having a bad value.
       #
       # The helper REPORTS the state; the policy below is this call site's own and stays visible
       # here. autopilot-build check 7 reads the same field through the same helper and treats
       # ABSENT as an abort — opposite to the branch below, and both are right (ADR-0076 §D2).
       # Do not "reconcile" the two.
       _st=$(bash "$_mfs" "$_m" hook_verified 2>/dev/null)
       _rc=$?
       [ "$_rc" -eq 0 ] || _st="UNREADABLE"     # exit 2/3: it did not run, same operator action
       case "$_st" in
         'PRESENT|True'|'PRESENT|False')
           : ;;                                     # the two valid values
         'ABSENT|completed')
           echo "note: $_m has no hook_verified field and is completed — it predates the field"
           echo "  (ADR-0016 added it to manifest-init.sh afterwards). A completed chain's dispatch"
           echo "  mode cannot affect this run, so the documented default (false) applies. Not an abort."
           ;;
         'ABSENT|'*)
           echo "✗ hook_verified: $_m has no hook_verified field and is NOT completed"
           echo "  (current_step=${_st#ABSENT|}) — a chain still in flight whose dispatch mode is unknown."
           echo "  This is not the pre-schema case; re-init the manifest or set the field explicitly."
           _bad=1
           ;;
         'UNREADABLE'|'')
           echo "✗ hook_verified: $_m could not be read — the check DID NOT RUN on it."
           echo "  Either the YAML is unparseable or python3/PyYAML is unavailable. This is not the"
           echo "  same as finding a bad value; fix the file or the interpreter and re-run."
           _bad=1
           ;;
         *)
           echo "✗ hook_verified: $_m has hook_verified=${_st#PRESENT|} (must be true/false)."
           echo "  A value is present and is neither — the manifest is corrupted or was hand-edited."
           _bad=1
           ;;
       esac
     done
     [ "$_bad" -eq 0 ] || exit 1
   fi
   ```
   (drives Workflow vs Agent-tool dispatch downstream, per manifest, exactly as before.)

   **Scope stays roadmap-wide, deliberately (ADR-0075 §D3).** Issue #123 raised narrowing the loop
   to the manifests of pending roadmap features. Rejected: that needs the PROJECT.md-feature →
   manifest mapping ADR-0030 already had to fix twice for suffix collisions, and a wrong mapping
   silently skips a manifest that matters. The absent-on-completed default removes the landmine
   without a lookup that can be wrong.
7. **`gh` authenticated:** `gh auth status` succeeds (needed to push and open PRs).
8. **CI + branch protection:** if `.github/workflows/ci.yml` is absent, drop the template
   (`~/.claude/templates/ci.yml` at runtime; source `staging/project-templates/ci/ci.yml`),
   substituting `__TEST_CMD__` with the trusted `.claude/test-cmd`, then run
   `~/.claude/hooks/set-branch-protection.sh`.

   **Then audit the WHOLE required set, not the `ci` context alone (issue #322, ADR-0114).** This
   step used to end *"verify the `ci` check is required on `main`"*, which was prose with no
   mechanism and named one context out of however many the branch requires — this repository's own
   `main` requires three, because `set-branch-protection.sh` unions exactly ONE into whatever is
   already there. A pre-flight that knows a third of the merge gate can pass while a PR the run
   opens is unmergeable.

   The authority is the **live** required set, derived, never a list declared in the opt-in marker:
   a declaration cannot lower what GitHub enforces, so one that disagrees is stale rather than
   lighter. A silently-added required check is caught by SATISFIABILITY instead — nothing produces
   it, so the audit aborts.

   <!-- fence-contract: nightly-autopilot-check-8 -->
   ```bash
   _rca="$HOME/.claude/hooks/required-checks-audit.sh"
   if [ ! -f "$_rca" ]; then
     echo "✗ check 8: required-checks-audit.sh not found at $_rca — the check DID NOT RUN."
     echo "  Run: bash staging/sync-to-claude.sh --apply"
     exit 1
   fi
   _out=$(bash "$_rca" --root "$PWD" 2>&1); _rc=$?
   printf '%s\n' "$_out"
   case "$_rc" in
     0) echo "✓ check 8: every required status check has a producer" ;;
     1) echo "✗ check 8: a required status check has no producer — a PR opened tonight would sit"
        echo "  pending forever and could not be merged in the morning."
        exit 1 ;;
     *) echo "✗ check 8: the audit DID NOT RUN (rc=$_rc). A roadmap does not start on an unknown"
        echo "  merge gate — an unread gate is not a clean gate."
        exit 1 ;;
   esac
   ```

   **`rc=3` aborts, and that is deliberate.** The audit reports "could not look" separately from
   "found nothing wrong" precisely so this branch can exist; treating them alike is the defect this
   check was rewritten to close. **`PASS` means every required context has a PRODUCER, never that
   it will be green** — nothing at launch time can know whether tomorrow's markdown lints. That
   half is the morning report's per-context reconciliation in §4.

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

The marker **records who armed it and when** (issue #321, ADR-0112). Its *presence* is still what
activates the guard — contents change nothing about that — but a marker that names its owner is the
difference between a stale one being diagnosable and being a mystery.

```bash
mkdir -p "$PWD/.claude/nightly-state"
# activates nightly-guard for this repo, and records the owner so a stale marker is identifiable
printf 'session_id=%s\nstarted_at=%s\n' \
  "${CLAUDE_CODE_SESSION_ID:-}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  > "$PWD/.claude/nightly-state/active"
: > "$PWD/.claude/nightly-state/build-status"      # cleared; set GREEN/RED after each test run
```

`started_at` for the morning report is read back from that marker. **Do not invent a separate file
for it.** Before ADR-0112 this step said only *"record `started_at`"* without naming a location, and
an orchestrator improvised `.claude/nightly-state/started-at` — a real file, in this repository right
now, written by nothing in the codebase and read by nothing either. A value with no specified home
gets one anyway, chosen by whoever runs the step.

**This marker outlives a run that dies.** Phase 2 is the only place that removes it, and a session
killed by context exhaustion, a crash, or the human pressing stop never reaches Phase 2 — so the
guard stays armed in the human's own later sessions. That is not a defect in the guard, which is
right to fail closed; the exit is `nightly-disarm.sh`, documented in the RUNBOOK under
*"The guard is still armed and I cannot push"*.

### 3.2 Print the `/goal` template

Print this for the human to paste (it keys off the status line the publish step prints, since the
`/goal` evaluator cannot call tools):

```
/goal "Every feature in PROJECT.md is [x], committed on feat/*, pushed, and a PR is open,
as shown by a NIGHTLY-PUBLISH line for each feature and no NIGHTLY-GUARD HALT line.
Or stop after <N> turns."
```

### 3.3 Drive project-conductor in roadmap-autopilot

Invoke `Skill(skill="project-conductor", args="nightly")`. The conductor (roadmap-autopilot mode) pre-authorizes
every pending feature, skips the per-feature Step 3 gate, and for each feature:
architecture (Gate 2, including Gate 2c's G13 external-dependency check — ADR-0060, resolved via
`~/.claude/hooks/external-dependency-check.sh`, the same script `concept-to-code/SKILL.md` Gate 2c
calls) → implement → review-triage-fix → local commit → `publish-feature.sh` (guard fires) → print
the `NIGHTLY-PUBLISH` status line → advance to the next `[ ]`.

**Marker contract (read by `nightly-guard`) — two markers, two different scopes, since ADR-0060
§D3 fixed a pre-existing latent defect (issue #114):**

- **Run-level `needs-human`** (`<root>/.claude/needs-human`): something is wrong with the *run*.
  On a feature that fails to reach `completed` for an unknown-state reason — a coder crash, an
  anti-test-weakening halt (ADR-0047 §D5, below) — the conductor writes this marker, and
  `nightly-guard` blocks that publish and **every subsequent one**. `rtf-blocker` and
  `token-budget` are the other two run-level halts (written by the review step and this skill's
  `/goal` overlay respectively) and behave the same way: once any of the three is set, the guard
  blocks every subsequent publish, so a HALT stops the whole roadmap rather than skipping one
  feature. A halted feature keeps its local commit but has no ready PR.
- **Per-feature `skipped-features`** (`<root>/.claude/nightly-state/skipped-features`,
  append-only): this *one* feature cannot proceed for a known, contained reason, and the roadmap
  continues to the next `[ ]`. **Five writers**, the last two added by ADR-0111 (issue #324):
  `spec-from-issue`'s thin-issue skip (Step 2), `spec-from-issue`'s injection-suspect skip
  (Step 1.5, ADR-0059), Gate 2c's G13 unprovisioned-dependency skip (ADR-0060 §D2 — see the
  "Marker" prose in `concept-to-code/SKILL.md`'s Gate 2c Autopilot-default block; it fires at each
  feature's own Gate 2c inside the per-feature chain this section drives, not literally inside §1.5
  Phase P, since dependencies are not declared until that feature's architect has run — noted here
  because it is this phase's skip mechanism being reused), `project-conductor` Step 4's
  **no-generated-SPEC skip**, and `project-conductor` Step 5 branch C's **`TERMINAL` entry-state
  skip**. `nightly-guard.sh` never reads this file: its presence has no effect on `--check`, by
  design (see the script's own v1.3 header comment). Every writer also marks the feature `[~]` in
  PROJECT.md with the same reason. The morning report lists these under `features_skipped[]`
  (schema v2.2, §4), separate from `guard_halts[]`.

  **Branch C is a split, not a downgrade** (ADR-0111): only a `TERMINAL` entry state — a chain that
  reached a *decided* end, its reason recorded in the manifest — takes the skip path. Every other
  state a feature can be left in is still a run-level `needs-human` halt, including the
  anti-test-weakening halt described below, which never transitions and so is never `TERMINAL`.

Before this ADR (issue #114), both writer classes above shared the run-level `needs-human` file, so
one thin issue silently halted every other feature in the roadmap — a latent defect, not a design
choice. If you find prose or a manifest describing a single shared marker, it predates this fix.

A Step 5 anti-test-weakening halt (ADR-0047 §D5) means the feature never reaches `completed` for an
unknown-state reason — the fix cycle touched something and the outcome cannot be trusted — so it
stays a **run-level** halt: the conductor writes `needs-human` exactly as it does for any other
feature that fails to complete, and the guard blocks that publish and every subsequent one. The
reason is recorded in `guard_halts[]` in the morning report. This skill runs no scan of its own —
detection happens once, inside `concept-to-code` Step 5, and this skill only surfaces the resulting
halt.

---

## 4. Phase 2 — Morning report and disarm

On every exit path, write `<project_root>/.claude/nightly-report.json` (schema v2.2: v2.1 fields
plus `features_skipped[]`, ADR-0060) with per-feature
`status`, `branch`, `commit_sha`, `pr_url`, `ci_status`, `guard_halt`, the `guard_halts[]` roll-up,
`features_skipped[]` (read from `<project_root>/.claude/nightly-state/skipped-features`, one entry
per line, `{feature, reason}` — additive and distinct from `guard_halts[]`: a skip did not stop the
roadmap, a halt did — §3.3 "Marker contract"), and `spend` (from the `/goal` overlay). Set
`ended_at` via `date -u`.

Also, per feature, `test_count_delta`, `deleted_lines`, `iteration_count`, `elapsed_wall_seconds`
(ADR-0064, issue #118) — additive, conditional-if-present, no schema bump: summed from that
feature's own `task_metrics` array in its `step5-report.json`, when present. These are METRICS,
not findings (ADR-0064 §D2): nothing in this Phase branches on them, they are never surfaced as
requiring action, and a feature whose `step5-report.json` carries no `task_metrics` leaves all
four fields absent on that feature entry — never `0` (ADR-0064 §D3).

Disarm the guard. This clears the whole transient set, not just the marker (ADR-0112): a
`build-status` left reading `RED` halts the in-script `--check` gate **regardless of the marker**,
and a `needs-human` left behind halts every publish — so removing only `active` leaves the next
session blocked by a file the disarm appeared to have handled.

```bash
bash ~/.claude/hooks/nightly-disarm.sh "$PWD"
```

It refuses (exit 1) if the marker was armed by a *different* session than the one running it. On this
path that cannot happen — this is the session that armed it — so a refusal here means the marker was
rewritten mid-run and is worth reporting rather than working around. Exit 3 means the disarm did not
run: report it, and do not treat the guard as cleared.

**Do not replace this with `rm -f`.** The plain remove is what this step used to be, and it is how a
`RED` build-status from a finished run reaches the next morning still halting things.

Emit one terminal line:
```
nightly-autopilot · <status> · report: <project_root>/.claude/nightly-report.json
```

Reconcile CI where possible: for each open PR, `gh pr checks <url>` maps **every required context**
to `green|red|pending`.

**`ci_status` is the AGGREGATE over the required set, not one check's colour (issue #322,
ADR-0114).** `red` if any required context is red, `pending` if any is pending, `green` only when
all are green, `unknown` when CI could not be queried. On a repo requiring a single check this is
byte-identical to what it has always been; on one requiring three it is the difference between a
correct value and a misleading one. This repository requires `markdownlint`, `links` and `ci`, and
before this a red `markdownlint` — real, PR #317 — reported as `green` and surfaced only when the
human tried to merge.

The per-context detail goes in an additive sibling, `required_checks`, so nothing that reads
`ci_status` has to change:

```json
"ci_status": "red",
"required_checks": { "ci": "green", "markdownlint": "red", "links": "green" }
```

The required set is the same live list pre-flight check 8 audited — read it with
`bash ~/.claude/hooks/required-checks-audit.sh --root "$PWD"`, whose `required:` lines carry it.
Do not re-derive it from `gh pr checks` output: that reports every check that ran, required or
not, and aggregating over those would let a non-blocking red check report the PR as unmergeable
when it is not.

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
