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
/skill project-conductor [autopilot]
```
No arguments (interactive): project root = `$PWD`, PROJECT.md path = `<project-root>/PROJECT.md`.

`autopilot` (roadmap-autopilot, ADR-0022): drives the whole roadmap unattended. Every pending feature
is pre-authorized as autopilot, the per-feature Step 3 gate is skipped, and after each feature's local
commit the publish step (`publish-feature.sh`) runs. Only launched by `autopilot` after its
pre-flight, which verifies the per-repo opt-in marker. Do not invoke `autopilot` by hand.

---

## Process

### Step 0 — Load and reconcile PROJECT.md

**Free variable, bound by the orchestrator: `_args`** — this skill's own argument string, exactly
as it was invoked (empty when it was invoked with none). Both parses below read it, and the
`autopilot` skill's §1.3 Phase S binds its own launch arguments the same way.

**This block's behaviour changes on purpose (issue #385, ADR-0132 §D2/§D5).** The mode detection
used to read the first positional parameter while the `--fork-from` scan walked the argument list
and read its length. Those are two different sources once the block is a fence: the renderer fills
in the first before the model ever sees the text, while the list and its length belong to the
shell that executes the fence — which has no positional parameters at all. **So neither parse has
ever worked as written** (audit §F1). The designed semantics are unchanged; what changes is that
they now happen.

<!-- fence-contract: conductor-step0-args -->
```bash
# ADR-0133 §D1 (issue #394): everything between the two FENCE_BASH lines runs under BASH, not
# under the host shell. The Bash tool executes a fence under whatever shell the session has — zsh
# 5.9 here — and zsh does not word-split an unquoted parameter expansion, so the parser call below
# received ONE argument where bash gives it four. This is the same fail-open shape `autopilot`
# Phase S carries, in a second skill, and the issue's own scanner could not see it. `export`
# forwards this body's caller-bound free variables across the new process boundary, since a plain
# shell variable does not survive it. The terminator sits at COLUMN 0 on purpose: an indented one
# is swallowed into the here-document and destroys this fence's exit code silently. Do not tidy
# either line.
export _args CLAUDE_PLUGIN_ROOT
bash <<'FENCE_BASH'
_root="$PWD"
_pmd="$_root/PROJECT.md"
# Both parses live in conductor-args.sh, because this markdown body is RENDERED before the model
# executes it and the renderer rewrites positional-parameter tokens in it. A file is never
# rendered. There is NO safe default if it cannot be resolved: false would prompt a human who is
# not present (the #329 class), true would run a whole roadmap unattended when nobody asked for
# that — so this refuses, which is what makes the fence abort-capable (ADR-0132 §D4/§D5).
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] \
   && [ -f "$CLAUDE_PLUGIN_ROOT/skills/project-conductor/scripts/conductor-args.sh" ]; then
  _ca="$CLAUDE_PLUGIN_ROOT/skills/project-conductor/scripts/conductor-args.sh"
elif [ -f "$HOME/.claude/skills/project-conductor/scripts/conductor-args.sh" ]; then
  _ca="$HOME/.claude/skills/project-conductor/scripts/conductor-args.sh"
else
  echo "CONDUCTOR-ARGS: DID-NOT-RUN — argument parser not deployed: conductor-args.sh"
  echo "  Run: bash <repo>/staging/sync-to-claude.sh --apply"
  exit 3
fi
# UNQUOTED on purpose, and the split is guaranteed BY THE WRAPPER above (issue #394, ADR-0133):
# this body runs under bash, which word-splits an unquoted expansion, which is what turns the
# argument string back into the separate tokens both parses expect. It stays unquoted for exactly
# that reason. Under the host shell there was no split at all, so the argument string arrived as
# one word and neither parse ever saw a flag. Quoting it would make `autopilot --fork-from main`
# one opaque word, which matches neither parse.
_ca_out=$(bash "$_ca" $_args) || {
  echo "CONDUCTOR-ARGS: DID-NOT-RUN — conductor-args.sh failed"
  echo "  Run: bash <repo>/staging/sync-to-claude.sh --apply"
  exit 3
}
# Roadmap-autopilot mode (ADR-0022): set by the `autopilot` argument.
_autopilot=$(printf '%s\n' "$_ca_out" | sed -n 's/^autopilot=//p')
# --fork-from <ref> (issue #364, ADR-0127 §D4): the base every feature branch is created from.
# Empty in attended mode and on any run that does not pass it, which is exactly today's behaviour.
_fork_from=$(printf '%s\n' "$_ca_out" | sed -n 's/^fork_from=//p')
# Scripts dir: plugin install uses $CLAUDE_PLUGIN_ROOT/scripts; the ~/.claude deployment
# keeps all shell helpers in ~/.claude/hooks. Prefer the plugin path, fall back to hooks.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/scripts/publish-feature.sh" ]; then
  _scripts="$CLAUDE_PLUGIN_ROOT/scripts"
else
  _scripts="$HOME/.claude/hooks"
fi
FENCE_BASH
```

**What this block hands on, and why it does not print it (ADR-0133 §D4).** The wrapper above runs
this body in a subprocess, so `_autopilot`, `_fork_from`, `_scripts` and `_root` die at the
terminator. Every later block that reads them already declares them *"bound by the orchestrator"* —
that contract is now literally true rather than true by the accident of a shared shell, and the
orchestrator carries the four values forward exactly as it carries `<topic-slug>`. §D4's usual
remedy is a printed token, and it is deliberately **not** used here: this block's success path is
asserted to be SILENT by an existing execution (`conductor-entry-failure-split.test.sh`, the CDA7
case, requires rc=0 with empty output), so a printed `autopilot=` line would break a green assertion
to satisfy a convention. Do not add one without moving that assertion first.

**If PROJECT.md does not exist:** go to Step 1 (setup).

**If PROJECT.md exists:**
1. Read the file.
2. **Reconcile completed manifests:** for every `- [ ] <feature>` line, derive its `topic-slug` (lowercase kebab, max 40 chars) and check:
   ```bash
   # ADR-0133 §D1 (issue #394): the body between the two FENCE_BASH lines runs under BASH, not under
   # the host shell, which is zsh here. `export` forwards `_root`; a plain shell variable does not
   # survive the new process boundary. The terminator sits at COLUMN 0 even though this fence is
   # indented inside a numbered list item: an indented terminator is swallowed into the here-document
   # and destroys this fence's exit code silently. Do not tidy it.
   # Divergent in MECHANISM, equivalent in OUTCOME today — stated so nobody later reads the wrapper
   # as fixing a symptom that was never observed. On an unmatched glob bash runs `ls` against the
   # literal pattern while zsh's `nomatch` declines to run it at all; either way `_cand` ends empty,
   # the script continues and the exit code is preserved. Measured: `2>/dev/null` does NOT suppress
   # zsh's `no matches found:` diagnostic, because the redirection belongs to the `ls` that never
   # runs. Wrapped because the divergence class is present, not because a symptom was seen.
   # NO `fence-contract` marker, deliberately (ADR-0133 §D3): this fence joins the wrapper population
   # through the divergence SCANNER, not through a declaration. It cannot halt a run, so `F3` asks it
   # for no marker, and adding one would create an `F4` execution obligation this feature did not
   # budget. The absence is a decision, not an oversight. (The standalone word for halting is avoided
   # on purpose: `fence_is_abort_capable` matches it as a whole word, so a comment SAYING this fence
   # cannot halt would classify it as one that can — rule 12.)
   export _root
   bash <<'FENCE_BASH'
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
FENCE_BASH
   ```

   **What this block hands on, and why it does not print it (ADR-0133 §D4).** The wrapper runs the
   body in a subprocess, so `_manifest` dies at the terminator; the instruction below reads it as a
   value the orchestrator carries from this block's own run, exactly as it carries `<topic-slug>`
   into it. §D4's usual remedy is a printed token, and it is deliberately **not** used: this lookup
   is one of three verbatim copies (here, Step 3's first check, and Step 5), and the Step 5 copy's
   no-match case is asserted to produce EMPTY output by an existing execution
   (`scope-guards.test.sh`, section B, case B6). A printed `MANIFEST=` line here would either break
   that assertion or split the three copies apart, and their being identical is what
   `scope-guards.test.sh` cases B1-B3 check. Do not add one without moving those assertions first.

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

**In `autopilot` mode this run may be bounded by `--features`/`--only` (issue #365, ADR-0129
§D1/§D2/§D4/§D5).** `autopilot` Phase 0 check 9 resolves the bound once, before Phase 1 starts, into
`.claude/autopilot-state/scope`; this gate reads that file, plus the same `published` ledger
`conductor-published-skip` reads immediately below. **It runs first, immediately before that check,
because an exhausted run ends regardless of which candidate is next** — exhaustion is a property of
the run, not of this particular slug — **and both checks read the same ledger**, so deciding "has
the run run out" before deciding "has THIS slug already published" settles the run-level question
first, rather than risking two fences drifting on what it means. The two do not share a single
read: this gate counts `published`'s lines, `conductor-published-skip` matches one slug in it.

This is a **CHECKER**: branch on its exit code. Exit 3 means the scope file exists but could not be
read, which is not the same as no scope file at all — an unbounded run.

**`scope` and `published` now survive a disarm (ADR-0167 §D4, issue #400).** `autopilot-disarm.sh`
no longer clears either file; only the next `autopilot` launch resets them, and it does so exactly
when it writes a fresh `scope` — a preserved bound is reused as-is, a spent one is replaced along
with the `published` ledger it goes with. This gate's own `DID-NOT-RUN` exit 3 above **stays a
halt** regardless: it fires *mid-run*, minutes after the launch wrote the file it is reading, where
an unreadable `scope` is an environment fault against a bound the operator already set, not the
ordinary "never had a bound" absence a launch tolerates. Same ABSENT/UNREADABLE state, two call
sites, opposite policies, both right (ADR-0167 §D5, CLAUDE.md rule 11).

<!-- fence-contract: conductor-scope-gate -->
```bash
# ADR-0133 §D1 (issue #394): everything between the two FENCE_BASH lines runs under BASH, not under
# the host shell, which is zsh here and differs from bash on word splitting, unmatched globs and
# `echo` escapes. `export` forwards this body's caller-bound free variables across the new process
# boundary; a plain shell variable does not survive it, and Step 0's fence — which binds
# `_autopilot` — is now a subprocess of its own, so the orchestrator carries these three in.
# Terminator at COLUMN 0; an indented one is swallowed into the here-document and destroys this
# fence's exit code silently.
export _root _feature _autopilot
bash <<'FENCE_BASH'
# Free variables, bound by the orchestrator: _root, _feature (the candidate roadmap line's exact
# text, no checkbox marker), _autopilot. Inert unless _autopilot=true.
_sf="$_root/.claude/autopilot-state/scope"
if [ "${_autopilot:-false}" != "true" ]; then
  echo "SCOPE-GATE: INACTIVE — attended mode, no bound is in effect."
elif [ ! -e "$_sf" ]; then
  echo "SCOPE-GATE: NONE — no scope file; this run is unbounded."
elif [ ! -r "$_sf" ]; then
  echo "SCOPE-GATE: DID-NOT-RUN — $_sf exists but cannot be read."
  exit 3
else
  _features=$(grep '^features=' "$_sf" | sed 's/^features=//' | head -1)
  case "$_features" in
    ''|*[!0-9]*) _features="" ;;
  esac
  _exhausted=0
  if [ -n "$_features" ]; then
    _pub="$_root/.claude/autopilot-state/published"
    if [ -e "$_pub" ]; then
      _delivered=$(grep -c . "$_pub" 2>/dev/null)
      case "$_delivered" in
        ''|*[!0-9]*) _delivered=0 ;;
      esac
    else
      _delivered=0
    fi
    [ "$_delivered" -ge "$_features" ] && _exhausted=1
  fi
  if [ "$_exhausted" = "1" ]; then
    echo "SCOPE-GATE: EXHAUSTED — $_delivered/$_features delivered."
    exit 2
  elif grep -q '^only=' "$_sf" 2>/dev/null; then
    if grep -qxF "only=$_feature" "$_sf"; then
      echo "SCOPE-GATE: IN-SCOPE — '$_feature' is in the only= list."
    else
      echo "SCOPE-GATE: OUT-OF-SCOPE — '$_feature' is not in the only= list."
      exit 1
    fi
  else
    echo "SCOPE-GATE: IN-SCOPE — no only= list; every row is in scope."
  fi
fi
FENCE_BASH
```

Branch on the exit code:
- **`0`** (`INACTIVE`, `NONE`, `IN-SCOPE`) → proceed to `conductor-published-skip`, below.
- **`1`** (`OUT-OF-SCOPE`) → skip this line and take the next `- [ ]`, exactly as `ALREADY`.
- **`2`** (`EXHAUSTED`) → emit `"project-conductor · SCOPE EXHAUSTED · <delivered>/<requested>"` and
  go to **Step 6B**. Write **no** `[~]`, **no** `skipped-features` entry and **no** `needs-human`.
- **`3`** (`DID-NOT-RUN`) → write `needs-human` with the printed reason and go to Step 6B.

**Why `2` writes nothing, and this supersedes ADR-0127 §D7 in part (ADR-0129 §D5).** ADR-0127 §D7
said a bounded run that runs out "marks the next feature `[~]`, appends to `skipped-features`, and
stops". Measured: Step 2 above always selects the **first** `- [ ]` line, so a `[~]` marker sitting
on the next feature is invisible to it **permanently** — under §D7's text every bounded run would
leave a feature behind that no later run ever picks up without a human editing `PROJECT.md` by hand,
quietly deleting work from the roadmap. A feature count is checked *between* features, never
mid-feature, so there is nothing half-attempted to mark and nothing to skip: the first unreached
feature simply stays `- [ ]`, ready for the next run. **The rest of §D7 is not superseded and still
stands: this branch must never write `needs-human`, and running out of budget must be the *least*
alarming way for a long session to end** — exactly like reaching the end of the roadmap at Step 7,
never like a fault.

**In `autopilot` mode the run's OWN ledger overrides the checkbox (issue #364, ADR-0127 §D4).**
`PROJECT.md` is marked `[x]` on the feature branch and never on the base the next feature forks
from, so the checkbox for a feature that just published still reads `[ ]` here and the loop would
re-pick it forever. The ledger is the run-scoped record of what this run has already published.

This is a **CHECKER**: branch on its exit code. Exit 3 means the ledger could not be read, which is
not the same as an empty ledger — a run that cannot tell what it has published must stop rather
than re-pick.

<!-- fence-contract: conductor-published-skip -->
```bash
# ADR-0133 §D1 (issue #394): the body between the two FENCE_BASH lines runs under BASH, not under
# the host shell. `export` forwards this body's caller-bound free variables across the new process
# boundary. Terminator at COLUMN 0; an indented one is swallowed into the here-document and destroys
# this fence's exit code silently, which here would turn a re-pick guard into a pass.
export _root _slug _autopilot
bash <<'FENCE_BASH'
# Free variables, bound by the orchestrator: _root, _slug (the candidate feature's topic slug),
# _autopilot. Inert unless _autopilot=true.
_led="$_root/.claude/autopilot-state/published"
if [ "${_autopilot:-false}" != "true" ]; then
  echo "PUBLISHED-SKIP: INACTIVE — attended mode, the checkbox is authoritative."
elif [ ! -e "$_led" ]; then
  # No ledger yet = nothing published in this run. Distinct from unreadable, below.
  echo "PUBLISHED-SKIP: NONE — no feature has published in this run yet."
elif [ ! -r "$_led" ]; then
  echo "PUBLISHED-SKIP: DID-NOT-RUN — $_led exists but cannot be read."
  exit 3
elif grep -qxF "$_slug" "$_led" 2>/dev/null; then
  echo "PUBLISHED-SKIP: ALREADY — '$_slug' published earlier in this run; advancing past it."
  exit 1
else
  echo "PUBLISHED-SKIP: PENDING — '$_slug' has not published in this run."
fi
FENCE_BASH
```

On `ALREADY` (exit 1), skip this line and take the next `- [ ]`; on `DID-NOT-RUN` (exit 3), write
`needs-human` and halt the run. Matching is `grep -qxF` — whole-line and literal, so a slug that is
a prefix of another (`102-requirement-ids` against `102-requirement-ids-coverage`) does not collide.

---

### Step 3 — HITL gate: confirm next feature

**Roadmap-autopilot bypass (ADR-0022):** if `_autopilot=true`, skip this entire gate. Set
`_autopilot=true` and go to Step 4. Authorization comes from the per-repo opt-in marker plus the
single evening launch of `autopilot`, verified before this skill was invoked; no per-feature
prompt is shown. If an in-progress manifest is at `step_4_session_boundary`, auto-resume it
(`Skill(skill="concept-to-code", args="resume <manifest-path>")`) instead of prompting. This bypass applies only
in `autopilot` mode; see the amended invariant below.

**First check — is there an in-progress manifest for `<next-feature>`?**

Derive `topic-slug` from `<next-feature>`. Look for:
```bash
# ADR-0133 §D1 (issue #394): the body between the two FENCE_BASH lines runs under BASH, not under
# the host shell, which is zsh here. `export` forwards `_root`; a plain shell variable does not
# survive the new process boundary. Terminator at COLUMN 0; an indented one is swallowed into the
# here-document and destroys this fence's exit code silently.
# Divergent in MECHANISM, equivalent in OUTCOME today — stated so nobody later reads the wrapper as
# fixing a symptom that was never observed. On an unmatched glob bash runs `ls` against the literal
# pattern while zsh's `nomatch` declines to run it at all; either way `_cand` ends empty, the script
# continues and the exit code is preserved. Measured: `2>/dev/null` does NOT suppress zsh's
# `no matches found:` diagnostic, because the redirection belongs to the `ls` that never runs, so
# that message reached this script's stderr unredirected. Wrapped because the divergence class is
# present, not because a symptom was seen.
# NO `fence-contract` marker, deliberately (ADR-0133 §D3): this fence joins the wrapper population
# through the divergence SCANNER, not through a declaration. It cannot halt a run, so `F3` asks it
# for no marker, and adding one would create an `F4` execution obligation this feature did not
# budget. The absence is a decision, not an oversight. (The standalone word for halting is avoided
# on purpose: `fence_is_abort_capable` matches it as a whole word, so a comment SAYING this fence
# cannot halt would classify it as one that can — rule 12.)
export _root
bash <<'FENCE_BASH'
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
FENCE_BASH
```

**What this block hands on, and why it does not print it (ADR-0133 §D4).** The wrapper runs the body
in a subprocess, so `_manifest` dies at the terminator; the instruction below reads it as a value the
orchestrator carries from this block's own run, exactly as it carries `<topic-slug>` into it. §D4's
usual remedy is a printed token, and it is deliberately **not** used: this lookup is one of three
verbatim copies (Step 0's reconciliation, here, and Step 5), and the Step 5 copy's no-match case is
asserted to produce EMPTY output by an existing execution (`scope-guards.test.sh`, section B, case
B6). A printed `MANIFEST=` line here would either break that assertion or split the three copies
apart, and their being identical is what `scope-guards.test.sh` cases B1-B3 check. Do not add one
without moving those assertions first.

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

Read `references/steps-4-7-chain-execution.md` when you reach Step 4 — it contains the full Step 4 through Step 7 content for this section.

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
- **NEVER skip the Step 3 HITL gate** — each feature requires explicit user confirmation before the chain starts. **Exception (ADR-0022):** in `autopilot` roadmap-autopilot mode the Step 3 gate is skipped; authorization comes from the per-repo opt-in marker plus the single evening launch of `autopilot`. In every other mode the gate is mandatory.
- **NEVER re-run setup** if PROJECT.md already exists.
- **NEVER mark `[x]` without verifying the manifest `current_step = completed`.**
