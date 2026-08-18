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

### Step 4 — Invoke concept-to-code

Emit: `"── Starting chain for: <next-feature> (autopilot: <on|off>) ──"`

**Fork point — check out `$_fork_from` BEFORE invoking the chain (issue #364, ADR-0127 §D4).**
Nothing downstream chooses a base: `commit --branch` in Gate 4.0 creates the feature branch from
whatever `HEAD` is when it runs, so the fork point is decided *here* or it is decided by accident.
Left to accident it is the previous feature's tip, which stacks PR *N* on features 1..*N*.

This is a **CHECKER**: branch on its exit code. Inert when `--fork-from` was not passed, so the
attended flow is byte-identical.

<!-- fence-contract: conductor-fork-point -->
```bash
# ADR-0133 §D1 (issue #394): the body between the two FENCE_BASH lines runs under BASH, not under
# the host shell. `export` forwards this body's caller-bound free variables across the new process
# boundary — `_fork_from` is one of the values Step 0's fence binds, and that fence is now a
# subprocess of its own, so the orchestrator carries it in. Terminator at COLUMN 0; an indented one
# is swallowed into the here-document and destroys this fence's exit code silently.
export _root _fork_from
bash <<'FENCE_BASH'
# Free variables: _root, _fork_from (empty unless --fork-from was passed).
if [ -z "${_fork_from:-}" ]; then
  echo "FORK-POINT: INACTIVE — no --fork-from; HEAD is used as-is (attended behaviour)."
elif ! git -C "$_root" rev-parse --verify --quiet "$_fork_from" >/dev/null 2>&1; then
  echo "FORK-POINT: DID-NOT-RUN — '$_fork_from' does not resolve in $_root."
  echo "  Phase P records this ref; a run whose base has vanished must stop, not fork from HEAD."
  exit 3
elif [ -n "$(git -C "$_root" status --porcelain 2>/dev/null)" ]; then
  echo "FORK-POINT: DIRTY — refusing to switch base with uncommitted changes present."
  exit 2
else
  git -C "$_root" checkout -q "$_fork_from" 2>/dev/null || {
    echo "FORK-POINT: DID-NOT-RUN — checkout of '$_fork_from' failed."; exit 3; }
  echo "FORK-POINT: ON — '$_fork_from'; this feature's branch forks from here."
fi
FENCE_BASH
```

`DID-NOT-RUN` (exit 3) and `DIRTY` (exit 2) are both run-level: write `needs-human` and halt. A run
that cannot place itself on the agreed base would silently produce a stacked branch, which is the
defect this fence exists to remove.

**Just-in-time SPEC copy (ADR-0023, autopilot only).** If `_autopilot=true`, resolve the feature's
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
the copy is `_autopilot=true` only. **It does not make this block redundant, and the difference is
which artifacts exist afterwards:** this guard settles the feature before any manifest is created,
where the c2c pre-flight has to create one and then abort it. Both outcomes are contained
per-feature skips; this one is cheaper and leaves no record to explain. Do not remove it on the
grounds that the chain now checks too.

This is a **CHECKER**: branch on its exit code. (`weakening-scan.sh`, invoked from `commit` Step 1,
is a REPORTER — it always exits 0 and signals `CLEAN` on stdout. Do not copy one block's branching
into the other.)

<!-- fence-contract: conductor-step4-nospec-skip -->
```bash
# ADR-0133 §D1 (issue #394): the body between the two FENCE_BASH lines runs under BASH, not under
# the host shell. The `ls "$_root"/docs/specs/…` glob below is a measured divergence: zsh's `nomatch`
# declines to run `ls` at all rather than passing the unmatched pattern through, and its diagnostic
# escapes the `2>/dev/null` that belongs to the command it never ran. `export` forwards this body's
# caller-bound free variables. Terminator at COLUMN 0; an indented one is swallowed into the
# here-document and destroys this fence's exit code silently.
export _root _feature CLAUDE_PLUGIN_ROOT
bash <<'FENCE_BASH'
# Free variables, bound by the orchestrator: _root (project root), _feature (the PROJECT.md feature
# line's text, without the "- [ ] " marker). Runs only when _autopilot=true.
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
# Mark [~] by EXACT string match, never a sed regex: a feature title is arbitrary GitHub text and
# can carry any sed metacharacter or delimiter. The program lives in mark-roadmap-skipped.sh
# because a bash fence in a SKILL.md is RENDERED before the model executes it, and the renderer
# substitutes the skill's own invocation arguments into it — so awk's whole-record reference was
# being replaced by an unrelated word at run time (issue #385, ADR-0132 §D1). It is the SAME file
# branch C loads: one question, one answer, so a row marked by one path and not the other is no
# longer expressible (ADR-0069-style extraction, ADR-0132 §D2). Resolved BEFORE the skip note is
# written, so an undeployed helper leaves no half-finished state behind.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] \
   && [ -f "$CLAUDE_PLUGIN_ROOT/skills/project-conductor/scripts/mark-roadmap-skipped.sh" ]; then
  _mrs="$CLAUDE_PLUGIN_ROOT/skills/project-conductor/scripts/mark-roadmap-skipped.sh"
elif [ -f "$HOME/.claude/skills/project-conductor/scripts/mark-roadmap-skipped.sh" ]; then
  _mrs="$HOME/.claude/skills/project-conductor/scripts/mark-roadmap-skipped.sh"
else
  echo "SPEC-COPY: DID-NOT-RUN — roadmap marker helper not deployed: mark-roadmap-skipped.sh"
  echo "  Run: bash <repo>/staging/sync-to-claude.sh --apply"
  exit 3
fi
# Per-feature skip note (ADR-0060 §D3), NEVER the run-level .claude/needs-human marker.
mkdir -p "$_root/.claude/autopilot-state"
printf 'issue #%s "%s" skipped: no generated SPEC at docs/specs/%s-*.spec.md\n' \
  "$_issue" "$_feature" "$_issue" >> "$_root/.claude/autopilot-state/skipped-features"
bash "$_mrs" "$_root/PROJECT.md" "$_feature" \
  || { echo "SPEC-COPY: DID-NOT-RUN — mark-roadmap-skipped.sh failed on $_root/PROJECT.md"; exit 3; }
echo "SPEC-COPY: SKIP no generated SPEC for issue #$_issue"
exit 1
FENCE_BASH
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
   # ADR-0133 §D1 (issue #394): the body between the two FENCE_BASH lines runs under BASH, not under
   # the host shell. `export` forwards this body's caller-bound free variables across the new process
   # boundary. The terminator sits at COLUMN 0 even though this fence is indented inside a numbered
   # list item: an indented terminator is swallowed into the here-document and destroys this fence's
   # exit code silently, which here would collapse four distinct routing outcomes into one. It is not
   # a formatting slip — do not tidy it.
   export _root _slug
   bash <<'FENCE_BASH'
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
FENCE_BASH
   ```
   - **`0`** → continue with step 2 below (`CREATE` → call `manifest-init.sh`; `ADOPT` → update the
     existing manifest in place).
   - **`1`** → contained per-feature skip: append the reason to
     `<root>/.claude/autopilot-state/skipped-features`, mark the feature `[~]` (through
     `mark-roadmap-skipped.sh`, resolved two-tier exactly as the block above resolves it — an exact
     whole-line match, never a sed regex), emit `"project-conductor · SKIP · <token>"`, and **return to
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
in a subprocess, so `_manifest` dies at the terminator. The instruction below reads it as a value the
orchestrator carries from this block's own run, exactly as it carries `<topic-slug>` into it — before
the wrapper it arrived only because the block and its reader happened to share a shell. §D4's usual
remedy is a printed token, and it is deliberately **not** used here: the no-match case is asserted to
produce EMPTY output by an existing execution (`scope-guards.test.sh`, section B, case B6), so a
printed `MANIFEST=` line would break a green assertion to satisfy a convention. Do not add one
without moving that assertion first.

Read `current_step` from `$_manifest` (empty falls into branch C below, exactly as today's 'manifest not found' case already does).

**A — `current_step = completed`:**
- **Capture the issue number FIRST, before the checkbox flip (issue #370, ADR-0128 §D2).** The
  roadmap line `roadmap-from-issues.sh` writes is `- [ ] <title>  (issue #N)`, and the flip below
  rewrites that line to end in `(completed: <date>)` — so reading the number afterwards can find
  nothing. Empty is the legitimate case for a roadmap that was not generated from issues, and it
  stays silent:
  ```bash
  _issue=$(grep -F -- "<next-feature>" "$_root/PROJECT.md" 2>/dev/null | head -1 \
    | sed -n 's/.*(issue #\([0-9][0-9]*\)).*/\1/p')
  # An empty result has two causes and only one of them is fine. A roadmap with NO issue markers
  # anywhere is the legitimate silent case; a roadmap that carries them and yielded none for THIS
  # feature is an extraction that did not work, which must not look identical to it.
  if [ -z "$_issue" ] && grep -q '(issue #' "$_root/PROJECT.md" 2>/dev/null; then
    printf 'note: PROJECT.md carries issue markers but none matched this feature — its PR will close nothing\n' >&2
  fi
  ```
- Update PROJECT.md: `- [ ] <next-feature>` → `- [x] <next-feature>  (completed: <YYYY-MM-DD>)` via bash sed.
- Emit: `"✓ <next-feature> complete."`
- **Roadmap-autopilot publish (ADR-0022):** if `_autopilot=true`, publish this feature before
  advancing. Record the test outcome for the guard, then run the publish helper (it calls
  `autopilot-guard.sh` itself and aborts on HALT):
  ```bash
  # Free variables, bound by the orchestrator: _root, _issue, and `_scripts` — the helper directory
  # Step 0 resolves. `_scripts` was declared nowhere until ADR-0133 §D4 asked which values cross a
  # block boundary: Step 0's block computes it and, now that every declared fence runs its body in
  # its own subprocess, cannot hand it over in-shell. Resolve it here if this block runs on its own:
  # "$CLAUDE_PLUGIN_ROOT/scripts" when that holds publish-feature.sh, else "$HOME/.claude/hooks".
  # build-status: GREEN because the chain reached `completed` only on a green test run.
  printf 'GREEN' > "$_root/.claude/autopilot-state/build-status"
  bash "$_scripts/publish-feature.sh" --slug "<topic-slug>" --issue "$_issue" \
    --base main --root "$_root"
  ```
  **`--issue` is passed unconditionally, empty value and all**, never wrapped in a
  `${_issue:+--issue $_issue}` conditional expansion. That idiom relies on word splitting to become
  two arguments, and **this shell may be zsh, where an unquoted expansion does not split** (issue
  #366) — the flag and its value would arrive as one argument and the parse would fail. An empty
  `--issue` is defined to mean "no closing reference", which is exactly the state an empty
  `$_issue` describes.
  **`--base main` is the PR BASE, not the fork point, and the two were being conflated (issue #364,
  ADR-0127 §D4).** Every feature PR targets `main`; every feature BRANCH forks from the run-scoped
  `autopilot/prep-<date>` created in `autopilot` Phase P. Keeping the PR base at `main` is what makes
  the PRs independently reviewable and mergeable in any order.

  **On success, append the slug to the run ledger — this is the producer Step 2's
  `conductor-published-skip` check consumes.** Without it that check reads an empty ledger for ever
  and the loop re-picks the feature that just published, because `PROJECT.md`'s `[x]` was written on
  the feature branch and is not visible from the base:
  ```bash
  mkdir -p "$_root/.claude/autopilot-state"
  printf '%s\n' "<topic-slug>" >> "$_root/.claude/autopilot-state/published"
  ```
  Append-only and never rewritten, so a re-run that crashes mid-roadmap still knows what shipped.

  **This append is also the `delivered` counter `conductor-scope-gate` reads, deliberately not a
  second counter (issue #365, ADR-0129 §D4).** `--features N` promises N publishes, never N
  attempts; a separate `delivered` file would be a second producer of the same fact, able to
  disagree with this one in the window between the push and its own write. If this ledger is ever
  optimised — deduplicated, rewritten in place, rotated, or replaced by an in-memory count — the
  scope gate's exhaustion check silently disagrees with what actually shipped: a shrunk or rewritten
  ledger under-reports `delivered` and the run overshoots its bound; a padded or duplicated one
  over-reports it and the run stops early, leaving reachable work `- [ ]` for no reason. Append-only,
  one line per publish, is what keeps `conductor-published-skip` and `conductor-scope-gate` — the
  two readers of this file — looking at the same fact.

  The helper prints a `AUTOPILOT-PUBLISH <slug> PR=<url>` line for the `/goal` evaluator and the
  morning report. If the helper exits non-zero (guard HALT or push/PR failure), the guard's halt
  conditions (`needs-human`, `rtf-blocker`, budget) are run-level, so STOP the roadmap: record the
  halt reason for the report, leave PROJECT.md as `[x]` (the code is committed locally, just not
  published), print the guard's `AUTOPILOT-GUARD HALT` line, and go to Step 6B. Do not attempt the
  next feature — a poisoned run-level marker would halt every subsequent publish anyway.
- **H16 — direction check (ADR-0061 §D2/§D3, issue #115).** Attended mode only (`_autopilot=false`)
  — autopilot has no human present and `/goal` cannot answer `AskUserQuestion` (ADR-0022), so this
  entire bullet is skipped when `_autopilot=true`. Runs here, right after "✓ `<next-feature>`
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
- **Roadmap-autopilot (ADR-0022, split by ADR-0111 / issue #324):** if `_autopilot=true`, this feature
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
  # ADR-0133 §D1 (issue #394): the body between the two FENCE_BASH lines runs under BASH, not under
  # the host shell. `export` forwards this body's caller-bound free variables across the new process
  # boundary. The terminator sits at COLUMN 0 even though this fence is indented inside a list item:
  # an indented terminator is swallowed into the here-document and destroys this fence's exit code
  # silently, which here would turn a run-level HALT into a contained SKIP. Do not tidy it.
  export _root _slug _feature _manifest CLAUDE_PLUGIN_ROOT
  bash <<'FENCE_BASH'
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
      # The [~] program lives in mark-roadmap-skipped.sh, the SAME file Step 4's skip loads: an
      # exact whole-line match, never a sed regex, because a feature title is arbitrary GitHub
      # text and can carry any sed metacharacter or delimiter. It is a file rather than a fence
      # because the renderer substitutes the skill's invocation arguments into awk's whole-record
      # reference (issue #385, ADR-0132 §D1/§D2). Resolved before anything is written, so an
      # undeployed helper leaves no half-finished state behind.
      if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] \
         && [ -f "$CLAUDE_PLUGIN_ROOT/skills/project-conductor/scripts/mark-roadmap-skipped.sh" ]; then
        _mrs="$CLAUDE_PLUGIN_ROOT/skills/project-conductor/scripts/mark-roadmap-skipped.sh"
      elif [ -f "$HOME/.claude/skills/project-conductor/scripts/mark-roadmap-skipped.sh" ]; then
        _mrs="$HOME/.claude/skills/project-conductor/scripts/mark-roadmap-skipped.sh"
      else
        echo "BRANCH-C: DID-NOT-RUN — roadmap marker helper not deployed: mark-roadmap-skipped.sh"
        echo "  Run: bash <repo>/staging/sync-to-claude.sh --apply"
        exit 3
      fi
      mkdir -p "$_root/.claude/autopilot-state"
      printf '%s skipped: chain reached a terminal state without completing (%s)\n' \
        "$_feature" "${_out#*|}" >> "$_root/.claude/autopilot-state/skipped-features"
      if [ -f "$_root/PROJECT.md" ]; then
        bash "$_mrs" "$_root/PROJECT.md" "$_feature" \
          || { echo "BRANCH-C: DID-NOT-RUN — mark-roadmap-skipped.sh failed on $_root/PROJECT.md"; exit 3; }
      fi
      echo "BRANCH-C: SKIP TERMINAL (${_out#*|}) — decided end, roadmap continues."
      exit 1 ;;
    *)
      # Everything else — NONE, ADOPTABLE, BOUNDARY, RESUMABLE, LATE, UNRESUMABLE, UNKNOWN,
      # UNREADABLE — is a state nobody decided. Run-level halt, exactly as before this split.
      mkdir -p "$_root/.claude/autopilot-state"
      printf 'RED' > "$_root/.claude/autopilot-state/build-status"
      printf 'feature "%s" did not reach completed (entry state: %s)\n' \
        "$_feature" "$_out" > "$_root/.claude/needs-human"
      echo "BRANCH-C: HALT ${_out%%|*} (${_out#*|}) — not a decided end; the outcome cannot be trusted."
      exit 2 ;;
  esac
FENCE_BASH
  ```
  - **`1`** (`SKIP`) → emit `"project-conductor · SKIP · <reason>"` and **return to Step 2** for the
    next `[ ]`. The reason reaches `features_skipped[]` in the morning report, not `guard_halts[]`.
  - **`2`** (`HALT`) → go to Step 6B and let `autopilot` write the morning report. Do not
    prompt, do not advance — a poisoned run-level marker would halt every subsequent publish anyway.
  - **`3`** (`DID-NOT-RUN`) → an unrun check is not a clean result. Write `needs-human` with the
    printed reason (the fence could not) and go to Step 6B.
- Otherwise (interactive): return to Step 3 (let user decide).

---

### Step 5b — Update the task ledger between features (ADR-0153)

Runs on **every advance**, after a roadmap row is marked `[x]` and before the next feature starts.
Placed here rather than in Step 6A because Step 6A is the session-boundary pause and does not run
on every outcome, and the question this answers — what is still open now that a feature closed — is
asked once per advance.

Invoke the `project-tasks` skill in its full mode against the project root. It regenerates the
`GitHub Issues` section from `gh`, folds in whatever the finished feature left behind, and proposes
promotions at its own approval gate. Under autopilot it still stops at that gate, so an unattended
run reports what it would have written and advances without writing.

**This is an INSTRUCTION, not an enforcement** (rule 16). Nothing executes it and no assertion can
observe that it happened; a harness pinning this paragraph pins only that it is written here.

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
- **NEVER skip the Step 3 HITL gate** — each feature requires explicit user confirmation before the chain starts. **Exception (ADR-0022):** in `autopilot` roadmap-autopilot mode the Step 3 gate is skipped; authorization comes from the per-repo opt-in marker plus the single evening launch of `autopilot`. In every other mode the gate is mandatory.
- **NEVER re-run setup** if PROJECT.md already exists.
- **NEVER mark `[x]` without verifying the manifest `current_step = completed`.**
