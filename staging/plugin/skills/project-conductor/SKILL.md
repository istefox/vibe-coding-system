---
name: project-conductor
description: Orchestrates a multi-feature project by running concept-to-code chains in sequence. Uses PROJECT.md as persistent state — [ ] pending, [x] completed. Re-invocation always resumes from the first pending feature. Handles the c2c session boundary (planning vs implementation).
triggers:
  - /skill project-conductor
  - project conductor
  - run all features in sequence
  - run project end to end
  - orchestrate project
---

# project-conductor — Multi-feature Project Orchestrator

Runs a multi-feature project one concept-to-code chain at a time.
`PROJECT.md` at the project root is the single source of truth: `[ ]` = pending, `[x]` = completed, `[~]` = skipped. Re-invoking the skill always resumes from the first pending feature.

## When to invoke
- First run: sets up PROJECT.md and starts the first chain.
- After returning from a fresh implementation session: re-invocation detects the completed manifest, reconciles PROJECT.md, and starts the next feature.
- Any time: to see project status or continue.

## Arguments
```
/skill project-conductor [nightly]
```
No arguments (interactive): project root = `$PWD`, PROJECT.md path = `<project-root>/PROJECT.md`.

`nightly` (roadmap-autopilot, ADR-0022): drives the whole roadmap unattended. Every pending feature
is pre-authorized as autopilot, the per-feature Step 3 gate is skipped, and after each feature's local
commit the publish step (`publish-feature.sh`) runs. Only launched by `nightly-autopilot` after its
pre-flight, which verifies the per-repo opt-in marker. Do not invoke `nightly` by hand.

---

## Process

### Step 0 — Load and reconcile PROJECT.md

```bash
_root="$PWD"
_pmd="$_root/PROJECT.md"
# Roadmap-autopilot mode (ADR-0022): set by the `nightly` argument.
_nightly=false; [ "$1" = "nightly" ] && _nightly=true
# Scripts dir: plugin install uses $CLAUDE_PLUGIN_ROOT/scripts; the ~/.claude deployment
# keeps all shell helpers in ~/.claude/hooks. Prefer the plugin path, fall back to hooks.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/scripts/publish-feature.sh" ]; then
  _scripts="$CLAUDE_PLUGIN_ROOT/scripts"
else
  _scripts="$HOME/.claude/hooks"
fi
```

**If PROJECT.md does not exist:** go to Step 1 (setup).

**If PROJECT.md exists:**
1. Read the file.
2. **Reconcile completed manifests:** for every `- [ ] <feature>` line, derive its `topic-slug` (lowercase kebab, max 40 chars) and check:
   ```bash
   # Anchor to the manifest naming convention (YYYY-MM-DD-<topic-slug>.manifest.yml) instead of a bare
   # substring glob, then verify the winning candidate's own topic: field equals the derived slug
   # exactly -- anchoring alone still lets one slug bind to a different slug sharing a hyphen-joined
   # prefix (e.g. "export" vs "export-csv"; SPEC.md finding 3.10).
   _slug="<topic-slug>"
   _cand=$(ls -t "$_root"/docs/manifests/????-??-??-"$_slug".manifest.yml 2>/dev/null | head -1)
   _manifest=""
   if [ -n "$_cand" ]; then
     _cand_topic=$(grep '^topic:' "$_cand" | sed 's/topic: *"//' | sed 's/".*//' | sed "s/topic: *//")
     [ "$_cand_topic" = "$_slug" ] && _manifest="$_cand"
   fi
   ```
   Read `current_step` from `$_manifest` (skip this feature's reconciliation if `$_manifest` is empty — no verified manifest exists for it yet). If `current_step = completed` → the chain ran but PROJECT.md was not updated (user skipped the Step 7 prompt). Auto-update: replace `- [ ] <feature>` with `- [x] <feature>  (completed: <YYYY-MM-DD>)` via bash sed. Emit: `"Auto-reconciled: <feature> ✓"`
3. After reconciliation: go to Step 2 (status).

---

### Step 1 — Setup interview (PROJECT.md absent)

Collect project metadata in two rounds of AskUserQuestion.

**Round 1:**
```
question: "New project setup — what is the project name?\n\nSelect 'Type in prompt' then enter the name in the next message."
header: "Project · Name"
options:
  - label: "Type in prompt"
    description: "Enter project name as the next message"
```
Wait for user message. Store as `<project-name>`.

**Round 2:**
```
question: "Project description — one sentence describing what this project does.\n\nSelect 'Type in prompt' then type it in the next message."
header: "Project · Description"
options:
  - label: "Type in prompt"
    description: "Enter description as the next message"
```
Wait for user message. Store as `<project-description>`.

**Round 3 — feature list:**
```
question: "List all features and phases.\n\nSelect 'Type in prompt' then enter your roadmap. Format:\n\nPhase 1 — Core\nFeature A\nFeature B\n\nPhase 2 — UI\nFeature C"
header: "Project · Roadmap"
options:
  - label: "Type in prompt"
    description: "Enter phases and features as the next message"
```
Wait for user message. Parse:
- Lines starting with `Phase` or `##` → new phase header
- All other non-empty lines → features within the current phase

Write PROJECT.md:
```markdown
# Project: <project-name>

## Overview
<project-description>

## Phases

### Phase 1 — <phase-name>
- [ ] Feature A
- [ ] Feature B

### Phase 2 — <phase-name>
- [ ] Feature C
```

Emit: `"PROJECT.md created at <_pmd>"`. Go to Step 2.

---

### Step 2 — Show project status

Count and display:

```
══════════════════════════════════
PROJECT: <name>
══════════════════════════════════
Phase 1 — <name>
  ✓ Feature A  (completed: 2026-06-01)
  ○ Feature B  ← NEXT
  ○ Feature C

Phase 2 — <name>
  ○ Feature D
══════════════════════════════════
Progress: 1 / 4 features complete
══════════════════════════════════
```

Symbols: `✓` = `[x]`, `○` = `[ ]`, `–` = `[~]`.

If ALL features are `[x]` or `[~]`: go to Step 7 (project complete).

Otherwise: find the first `- [ ]` line. Extract `<next-feature>` and `<next-phase>`. Go to Step 3.

---

### Step 3 — HITL gate: confirm next feature

**Roadmap-autopilot bypass (ADR-0022):** if `_nightly=true`, skip this entire gate. Set
`_autopilot=true` and go to Step 4. Authorization comes from the per-repo opt-in marker plus the
single evening launch of `nightly-autopilot`, verified before this skill was invoked; no per-feature
prompt is shown. If an in-progress manifest is at `step_4_session_boundary`, auto-resume it
(`Skill(skill="concept-to-code", args="resume <manifest-path>")`) instead of prompting. This bypass applies only
in `nightly` mode; see the amended invariant below.

**First check — is there an in-progress manifest for `<next-feature>`?**

Derive `topic-slug` from `<next-feature>`. Look for:
```bash
# Anchor to the manifest naming convention (YYYY-MM-DD-<topic-slug>.manifest.yml) instead of a bare
# substring glob, then verify the winning candidate's own topic: field equals the derived slug
# exactly -- anchoring alone still lets one slug bind to a different slug sharing a hyphen-joined
# prefix (e.g. "export" vs "export-csv"; SPEC.md finding 3.10).
_slug="<topic-slug>"
_cand=$(ls -t "$_root"/docs/manifests/????-??-??-"$_slug".manifest.yml 2>/dev/null | head -1)
_manifest=""
if [ -n "$_cand" ]; then
  _cand_topic=$(grep '^topic:' "$_cand" | sed 's/topic: *"//' | sed 's/".*//' | sed "s/topic: *//")
  [ "$_cand_topic" = "$_slug" ] && _manifest="$_cand"
fi
```
Read `current_step` from `$_manifest` (empty means no verified in-progress manifest — fall through to the standard gate below, exactly as the existing 'no manifest' path already does):

- If `current_step = step_4_session_boundary`: the planning phase already ran. Offer to resume:
  ```
  question: "Resume in-progress chain for '<next-feature>'?\n\nManifest: <manifest-path>\nStatus: planning complete, awaiting fresh session for implementation.\n\nResume will invoke concept-to-code resume."
  header: "Conductor · Resume"
  options:
    - label: "Resume implementation"
      description: "Invoke: /skill concept-to-code resume <manifest-path>"
    - label: "Stop here"
      description: "Exit — re-invoke project-conductor when ready"
  ```
  - "Resume implementation": invoke `Skill(skill="concept-to-code", args="resume <manifest-path>")`. Go to Step 5.
  - "Stop here": emit stop message (see Step 6B). Exit.

- Otherwise (no manifest or other state): show the standard gate below.

**Standard gate:**
```
question: "project-conductor — Start next feature?\n\nFeature: <next-feature>\nPhase: <next-phase>\n\nThis will invoke concept-to-code for this feature."
header: "Conductor · Next"
options:
  - label: "Start — <next-feature>"
    description: "Invoke concept-to-code normally (HITL gates active)"
  - label: "Start in autopilot mode"
    description: "Run unattended: all HITL gates auto-approved, commit auto-executed. Use for overnight runs."
  - label: "Skip this feature"
    description: "Mark [~] skipped, move to the next pending feature"
  - label: "Stop here"
    description: "Exit — re-invoke /skill project-conductor to continue later"
```

- **"Stop here"**: go to Step 6B (pause message). Exit.
- **"Skip this feature"**: replace `- [ ] <next-feature>` with `- [~] <next-feature>  (skipped)` in PROJECT.md via bash sed. Return to Step 2.
- **"Start"**: go to Step 4 with `_autopilot=false`.
- **"Start in autopilot mode"**: set `_autopilot=true`. Go to Step 4.

---

### Step 4 — Invoke concept-to-code

Emit: `"── Starting chain for: <next-feature> (autopilot: <on|off>) ──"`

**Just-in-time SPEC copy (ADR-0023, nightly only).** If `_nightly=true`, resolve the feature's
generated spec **by its issue number** (never by re-deriving the slug from the feature text, which
would not match the roadmap's number-prefixed slug) and copy it to the single path c2c autopilot
reads. Features run sequentially, so there is no collision, and this feature's SPEC is committed in
its PR.

**A missing spec is a KNOWN, CONTAINED, per-feature problem and is settled HERE (ADR-0111, issue
#324) — not passed downstream.** Before that feature existed, this block printed a log line and
invoked the chain anyway, on the stated belief that *"the c2c autopilot pre-flight hard-aborts at
Gate 0 for a missing SPEC.md"*. At the time that was false: with no SPEC, `gate0-detect.sh` reports
`spec_adr_exist=false`, the chain routed greenfield, and Step 1 dispatched `interview-driver`, which
is interactive — on a path with nobody to answer it. The chain then failed to complete, Step 5 branch
C called that an unknown state, and one feature with a thin issue halted every feature behind it.
**The evidence lives here and only here**: by the time branch C runs, the manifest reads
`step_0_init`/`in_progress`, indistinguishable from any other mid-flight state. This is the issue's
own instruction — move the classification to where the evidence is — applied.

**As of issue #329 / ADR-0115 the chain does abort, and this block still runs first and stays
primary.** `concept-to-code` §2 Form A step 7b is an unattended routing pre-flight: with
`autopilot = true` and no `SPEC.md` it transitions the manifest to `aborted` and exits 1. That
closes the same hole from the other end, for every route to `autopilot = true` — including the
attended *"Start in autopilot mode"* branch of Step 3, which never reaches the copy below because
the copy is `_nightly=true` only. **It does not make this block redundant, and the difference is
which artifacts exist afterwards:** this guard settles the feature before any manifest is created,
where the c2c pre-flight has to create one and then abort it. Both outcomes are contained
per-feature skips; this one is cheaper and leaves no record to explain. Do not remove it on the
grounds that the chain now checks too.

This is a **CHECKER**: branch on its exit code. (`weakening-scan.sh`, invoked from `commit` Step 1,
is a REPORTER — it always exits 0 and signals `CLEAN` on stdout. Do not copy one block's branching
into the other.)

<!-- fence-contract: conductor-step4-nospec-skip -->
```bash
# Free variables, bound by the orchestrator: _root (project root), _feature (the PROJECT.md feature
# line's text, without the "- [ ] " marker). Runs only when _nightly=true.
# Extract the issue number from the "(issue #N)" suffix of the feature line.
_issue=$(printf '%s' "$_feature" | sed -n 's/.*(issue #\([0-9][0-9]*\)).*/\1/p')
if [ -z "$_issue" ]; then
  # No "(issue #N)" suffix = pre-designed mode: SPEC.md is already at the root, leave it untouched.
  echo "SPEC-COPY: PREDESIGNED — no issue suffix; leaving SPEC.md as it is."
  exit 0
fi
_spec=$(ls "$_root"/docs/specs/"$_issue"-*.spec.md 2>/dev/null | head -1)
if [ -n "$_spec" ] && [ -f "$_spec" ]; then
  cp "$_spec" "$_root/SPEC.md" || { echo "SPEC-COPY: DID-NOT-RUN — could not copy $_spec"; exit 3; }
  echo "SPEC-COPY: OK $_spec"
  exit 0
fi
[ -f "$_root/PROJECT.md" ] || { echo "SPEC-COPY: DID-NOT-RUN — no PROJECT.md at $_root"; exit 3; }
# Per-feature skip note (ADR-0060 §D3), NEVER the run-level .claude/needs-human marker.
mkdir -p "$_root/.claude/nightly-state"
printf 'issue #%s "%s" skipped: no generated SPEC at docs/specs/%s-*.spec.md\n' \
  "$_issue" "$_feature" "$_issue" >> "$_root/.claude/nightly-state/skipped-features"
# Mark [~] by EXACT string match, never a sed regex: a feature title is arbitrary GitHub text and
# can carry any sed metacharacter or delimiter.
awk -v f="$_feature" '{ if ($0 == "- [ ] " f) print "- [~] " f "  (skipped)"; else print }' \
  "$_root/PROJECT.md" > "$_root/PROJECT.md.tmp" && mv "$_root/PROJECT.md.tmp" "$_root/PROJECT.md"
echo "SPEC-COPY: SKIP no generated SPEC for issue #$_issue"
exit 1
```

Branch on the exit code:
- **`0`** (`OK`, `PREDESIGNED`) → proceed to the autopilot/manual invocation below.
- **`1`** (`SKIP`) → the feature is marked `[~]`, the reason is in `skipped-features`, and the morning
  report picks it up under `features_skipped[]`. Emit
  `"project-conductor #<n> · SKIP · no generated SPEC"` and **return to Step 2** for the next `[ ]`.
  Do NOT invoke `concept-to-code`, and do NOT write `needs-human`.
- **`3`** (`DID-NOT-RUN`) → the check did not run, which is not the same as nothing to skip. Treat as
  run-level: write `needs-human` with the printed reason and go to Step 6B.

If `_autopilot=true`:
1. **Entry-state guard before creating anything (ADR-0111).** `concept-to-code` step 4b classifies an
   existing manifest before `manifest-init.sh` runs (ADR-0109), but this skill calls `manifest-init.sh`
   **itself**, outside that guard — so a same-day slug collision here still returned a bare exit 2 with
   no token. Same classifier, same shape, one step earlier. **CHECKER.**

   <!-- fence-contract: conductor-step4-init-guard -->
   ```bash
   # Free variables: _root (project root), _slug (this feature's topic-slug).
   _mes="$HOME/.claude/skills/concept-to-code/scripts/manifest-entry-state.sh"
   if [ ! -f "$_mes" ]; then
     echo "ENTRY-INIT: DID-NOT-RUN — classifier missing: $_mes"
     echo "  Run: bash <repo>/staging/sync-to-claude.sh --apply"
     exit 3
   fi
   # Constructed here because it must be known BEFORE manifest-init.sh runs, which is the one thing
   # that construction is for; manifest-init.sh's own exit 2 stays the backstop for a date roll.
   _man="$_root/docs/manifests/$(date +%Y-%m-%d)-$_slug.manifest.yml"
   _out=$(bash "$_mes" "$_man" 2>&1); _rc=$?
   [ "$_rc" -eq 0 ] || { echo "ENTRY-INIT: DID-NOT-RUN — $_out"; exit 3; }
   case "${_out%%|*}" in
     NONE)
       echo "ENTRY-INIT: CREATE — no manifest for this slug today; manifest-init.sh may run."
       exit 0 ;;
     TERMINAL)
       echo "ENTRY-INIT: TERMINAL (${_out#*|}) — this slug already ran to a decided end today."
       exit 1 ;;
     UNKNOWN|UNREADABLE)
       echo "ENTRY-INIT: ${_out%%|*} (${_out#*|}) — the manifest does not parse, or names a state"
       echo "  the validator does not recognise. Do not route it."
       exit 2 ;;
     *)
       echo "ENTRY-INIT: ADOPT ($_out) — a manifest for this slug is in flight today."
       echo "  Update it in place; do NOT call manifest-init.sh, it would exit 2."
       exit 0 ;;
   esac
   ```
   - **`0`** → continue with step 2 below (`CREATE` → call `manifest-init.sh`; `ADOPT` → update the
     existing manifest in place).
   - **`1`** → contained per-feature skip: append the reason to
     `<root>/.claude/nightly-state/skipped-features`, mark the feature `[~]` (the exact-match `awk`
     idiom above, never a sed regex), emit `"project-conductor · SKIP · <token>"`, and **return to
     Step 2**. Never `needs-human`.
   - **`2`** or **`3`** → run-level: write `needs-human` with the printed reason and go to Step 6B.
2. Set `autopilot: true` in the manifest via bash sed (create the manifest via `manifest-init.sh` on
   `CREATE`; update it in place on `ADOPT`).
3. Emit: `"Autopilot mode ON — all HITL gates will be auto-approved."`
4. Invoke: `Skill(skill="concept-to-code", args="<next-feature>")`.

If `_autopilot=false`:
1. Invoke: `Skill(skill="concept-to-code", args="<next-feature>")`.

**Immediately after concept-to-code returns (do NOT wait for user input):** go to Step 5.

---

### Step 5 — Evaluate chain outcome

Find the manifest:
```bash
# Anchor to the manifest naming convention (YYYY-MM-DD-<topic-slug>.manifest.yml) instead of a bare
# substring glob, then verify the winning candidate's own topic: field equals the derived slug
# exactly -- anchoring alone still lets one slug bind to a different slug sharing a hyphen-joined
# prefix (e.g. "export" vs "export-csv"; SPEC.md finding 3.10).
_slug="<topic-slug>"
_cand=$(ls -t "$_root"/docs/manifests/????-??-??-"$_slug".manifest.yml 2>/dev/null | head -1)
_manifest=""
if [ -n "$_cand" ]; then
  _cand_topic=$(grep '^topic:' "$_cand" | sed 's/topic: *"//' | sed 's/".*//' | sed "s/topic: *//")
  [ "$_cand_topic" = "$_slug" ] && _manifest="$_cand"
fi
```
Read `current_step` from `$_manifest` (empty falls into branch C below, exactly as today's 'manifest not found' case already does).

**A — `current_step = completed`:**
- Update PROJECT.md: `- [ ] <next-feature>` → `- [x] <next-feature>  (completed: <YYYY-MM-DD>)` via bash sed.
- Emit: `"✓ <next-feature> complete."`
- **Roadmap-autopilot publish (ADR-0022):** if `_nightly=true`, publish this feature before
  advancing. Record the test outcome for the guard, then run the publish helper (it calls
  `nightly-guard.sh` itself and aborts on HALT):
  ```bash
  # build-status: GREEN because the chain reached `completed` only on a green test run.
  printf 'GREEN' > "$_root/.claude/nightly-state/build-status"
  bash "$_scripts/publish-feature.sh" --slug "<topic-slug>" --base main --root "$_root"
  ```
  The helper prints a `NIGHTLY-PUBLISH <slug> PR=<url>` line for the `/goal` evaluator and the
  morning report. If the helper exits non-zero (guard HALT or push/PR failure), the guard's halt
  conditions (`needs-human`, `rtf-blocker`, budget) are run-level, so STOP the roadmap: record the
  halt reason for the report, leave PROJECT.md as `[x]` (the code is committed locally, just not
  published), print the guard's `NIGHTLY-GUARD HALT` line, and go to Step 6B. Do not attempt the
  next feature — a poisoned run-level marker would halt every subsequent publish anyway.
- **H16 — direction check (ADR-0061 §D2/§D3, issue #115).** Attended mode only (`_nightly=false`)
  — nightly has no human present and `/goal` cannot answer `AskUserQuestion` (ADR-0022), so this
  entire bullet is skipped when `_nightly=true`. Runs here, right after "✓ `<next-feature>`
  complete", because `$_manifest` (the feature that just finished) and
  `$_root/.claude/step5-report.json` (that same feature's Step 5 report) are both still the
  CURRENT feature's — the next chain's own Step 5 overwrites the report before this skill would
  ever get back here to compare two features' worth of it. See
  `h16-direction-check.sh`'s own header for exactly what is and is not reachable across features
  at this seam, and why (Task 4 finding, issue #115): only `tracer_bullet_verdict` genuinely
  accumulates across the whole roadmap (it is manifest-persisted, one file per feature, never
  overwritten); `budget_findings`/out-of-scope/`suspect_findings` are same-feature evidence only.
  ```bash
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/skills/project-conductor/scripts/h16-direction-check.sh" ]; then
    _h16="$CLAUDE_PLUGIN_ROOT/skills/project-conductor/scripts/h16-direction-check.sh"
  elif [ -f "$HOME/.claude/skills/project-conductor/scripts/h16-direction-check.sh" ]; then
    _h16="$HOME/.claude/skills/project-conductor/scripts/h16-direction-check.sh"
  else
    _h16=""    # neither resolves — no H16 evidence check; an un-synced machine keeps today's behaviour
  fi
  h16_out=""
  [ -n "$_h16" ] && h16_out=$(bash "$_h16" --root "$_root" --this-manifest "$_manifest")
  ```
  If `$h16_out` carries no `^TRIGGER` line (i.e. is `CLEAN`, absent script, or resolution failed):
  do nothing, no question, no log line, continue below. **This silence is the point** — H16 exists
  to ask when there is a reason to, and an unconditional "still on track?" every single feature is
  exactly the furniture ADR-0061 §D2 rejects. Never `[ -n "$h16_out" ]` (true even on `CLEAN`,
  same trap `weakening_findings` already documents at the commit call site) — always
  `printf '%s\n' "$h16_out" | grep -q '^TRIGGER'`.

  If at least one `TRIGGER` line is present, ask (do NOT auto-answer or auto-complete):
  ```
  question: "H16 — direction check\n\nEvidence:\n<one line per TRIGGER, verbatim — the 3rd
    tab-separated field of each>\n\nIs this still the right direction for the roadmap?"
  header: "Conductor · Direction"
  options:
    - label: "Continue"
      description: "Keep going with the roadmap as planned"
    - label: "Pause and reconsider"
      description: "Stop here — re-evaluate before starting the next feature"
  ```
  Record the answer by emitting it in the transcript (`"H16: <answer>"`) — no new manifest field,
  no new advisory array (issue #115 Task 3 constraint; ADR-0052 §D5). "Continue": fall through to
  "On success, return to Step 2" below, unchanged. "Pause and reconsider": go to Step 6B (paused)
  instead of Step 2. **H16 never halts on its own** (§D3, every input above is a heuristic) — a
  human choosing to pause is the human's decision, not the gate's.
- On success, return to Step 2.

**B — `current_step = step_4_session_boundary`:**
- If `_autopilot=true`: emit `"── Session boundary: resuming automatically (autopilot) ──"`. Immediately invoke `Skill(skill="concept-to-code", args="resume <manifest-path>")`. **Immediately after it returns, go back to Step 5 to re-evaluate outcome.**
- If `_autopilot=false`: emit the session boundary message (Step 6A). Exit.

**C — manifest not found or unexpected state:**
- Emit: `"Warning: could not determine outcome for '<next-feature>' (manifest state: <current_step>). PROJECT.md not updated."`
- **Roadmap-autopilot (ADR-0022, split by ADR-0111 / issue #324):** if `_nightly=true`, this feature
  did not reach a clean `completed`, so it is not publishable — but *not publishable* and *the run
  cannot be trusted* are different claims, and this branch used to make only the second one. Writing
  the run-level `needs-human` marker unconditionally meant one wedged feature in a twelve-feature
  wave cost the eleven behind it, which is the blast radius ADR-0060 §D3 already removed from
  `spec-from-issue`'s two skips and from Gate 2c's. Classify first, then decide.

  **The token alone decides, and no timestamp is compared.** A `TERMINAL` manifest is a *decided*
  end with its reason recorded in the manifest — a pre-existing chain for this slug, Gate 4.5's
  autopilot hand-code abort on a red tracer probe, Express Gate E3's abort. A crash leaves a
  **non-terminal** state, so it is caught by the fallthrough below; ADR-0047 §D5's weakening halt
  never transitions and therefore stays run-level with no special case for it here. Separating "a
  previous run's terminal manifest" from "this run's chain aborted" would need an mtime comparison
  that buys nothing (both are decided ends) and breaks on any `git checkout`.

  Read the state through `manifest-entry-state.sh`, never with a bare `grep current_step` — Form C
  sets `status: aborted` and leaves `current_step` untouched, so reading one field reports a
  terminal chain as `step_0_init` (ADR-0109; ADR-0076 §THE RULE). **CHECKER.**

  <!-- fence-contract: conductor-branch-c-entry-classify -->
  ```bash
  # Free variables: _root (project root), _slug (this feature's topic-slug), _feature (the
  # PROJECT.md feature line's text), _manifest (the resolved manifest path, MAY BE EMPTY).
  _mes="$HOME/.claude/skills/concept-to-code/scripts/manifest-entry-state.sh"
  if [ ! -f "$_mes" ]; then
    echo "BRANCH-C: DID-NOT-RUN — classifier missing: $_mes"
    echo "  Run: bash <repo>/staging/sync-to-claude.sh --apply"
    exit 3
  fi
  _target="$_manifest"
  [ -n "$_target" ] || _target="$_root/docs/manifests/$(date +%Y-%m-%d)-$_slug.manifest.yml"
  _out=$(bash "$_mes" "$_target" 2>&1); _rc=$?
  [ "$_rc" -eq 0 ] || { echo "BRANCH-C: DID-NOT-RUN — $_out"; exit 3; }
  case "${_out%%|*}" in
    TERMINAL)
      # Known, contained, per-feature: the chain reached a decided end. Roadmap continues.
      mkdir -p "$_root/.claude/nightly-state"
      printf '%s skipped: chain reached a terminal state without completing (%s)\n' \
        "$_feature" "${_out#*|}" >> "$_root/.claude/nightly-state/skipped-features"
      if [ -f "$_root/PROJECT.md" ]; then
        awk -v f="$_feature" '{ if ($0 == "- [ ] " f) print "- [~] " f "  (skipped)"; else print }' \
          "$_root/PROJECT.md" > "$_root/PROJECT.md.tmp" && mv "$_root/PROJECT.md.tmp" "$_root/PROJECT.md"
      fi
      echo "BRANCH-C: SKIP TERMINAL (${_out#*|}) — decided end, roadmap continues."
      exit 1 ;;
    *)
      # Everything else — NONE, ADOPTABLE, BOUNDARY, RESUMABLE, LATE, UNRESUMABLE, UNKNOWN,
      # UNREADABLE — is a state nobody decided. Run-level halt, exactly as before this split.
      mkdir -p "$_root/.claude/nightly-state"
      printf 'RED' > "$_root/.claude/nightly-state/build-status"
      printf 'feature "%s" did not reach completed (entry state: %s)\n' \
        "$_feature" "$_out" > "$_root/.claude/needs-human"
      echo "BRANCH-C: HALT ${_out%%|*} (${_out#*|}) — not a decided end; the outcome cannot be trusted."
      exit 2 ;;
  esac
  ```
  - **`1`** (`SKIP`) → emit `"project-conductor · SKIP · <reason>"` and **return to Step 2** for the
    next `[ ]`. The reason reaches `features_skipped[]` in the morning report, not `guard_halts[]`.
  - **`2`** (`HALT`) → go to Step 6B and let `nightly-autopilot` write the morning report. Do not
    prompt, do not advance — a poisoned run-level marker would halt every subsequent publish anyway.
  - **`3`** (`DID-NOT-RUN`) → an unrun check is not a clean result. Write `needs-human` with the
    printed reason (the fence could not) and go to Step 6B.
- Otherwise (interactive): return to Step 3 (let user decide).

---

### Step 6A — Session boundary pause

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PLANNING COMPLETE: <next-feature>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Manifest: <manifest-path>

The concept-to-code chain has crossed the session boundary.
To continue:

  1. Open a FRESH Claude Code session in:
     <project-root>

  2. Run:
     /skill concept-to-code resume <manifest-path>

  3. Complete the implementation (Steps 5–7 of the chain).

  4. After the commit, return here and run:
     /skill project-conductor

The conductor will detect the completed manifest, update PROJECT.md,
and start the next feature automatically.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Exit.

---

### Step 6B — Conductor paused

```
project-conductor paused at: <next-feature>
Re-invoke /skill project-conductor to continue from this feature.
```

Exit.

---

### Step 7 — All features complete

```
═══════════════════════════════════════════
PROJECT COMPLETE: <project-name>
All <N> features implemented.
═══════════════════════════════════════════
```

Exit.

---

## PROJECT.md format reference

```markdown
# Project: <name>

## Overview
<one-sentence description>

## Phases

### Phase 1 — <name>
- [ ] Pending feature
- [x] Completed feature  (completed: 2026-06-02)
- [~] Skipped feature  (skipped)

### Phase 2 — <name>
- [ ] Another feature
```

---

## Invariants

- **NEVER start a chain for a feature marked `[x]` or `[~]`.**
- **NEVER modify PROJECT.md with the Edit tool** — always bash sed substitution.
- **NEVER skip the Step 3 HITL gate** — each feature requires explicit user confirmation before the chain starts. **Exception (ADR-0022):** in `nightly` roadmap-autopilot mode the Step 3 gate is skipped; authorization comes from the per-repo opt-in marker plus the single evening launch of `nightly-autopilot`. In every other mode the gate is mandatory.
- **NEVER re-run setup** if PROJECT.md already exists.
- **NEVER mark `[x]` without verifying the manifest `current_step = completed`.**
