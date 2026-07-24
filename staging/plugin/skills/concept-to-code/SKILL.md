---
name: concept-to-code
description: Use this skill when a non-trivial feature must be designed and implemented end-to-end via the multi-agent chain (interview → architecture → project memory → fresh session → implementation → optional review). Orchestrates interview-driver, architect, claude-md-generator, coder agents with explicit HITL gates and YAML manifest persistence cross-session. Triggers: "/skill concept-to-code", "run the chain", "concept to code end-to-end", "new feature end-to-end".
---

# `concept-to-code` — Orchestrator Skill

Codifies the concept→code workflow (blueprint §11) as a deterministic state machine
with YAML manifest persistence, explicit HITL gates, and dispatch to existing agents.

**Manifest schema version in use: `manifest_schema_version: "1.3"` (the validator accepts `1.0|1.1|1.2|1.3`; all prior fields are backward-compatible; `chain_path` is the new 1.3 routing field)**

---

## Skill isolation — no superpowers check during the chain

**THIS CHAIN IS A SELF-CONTAINED WORKFLOW.** While `concept-to-code` is active:

- **Do NOT invoke** `writing-plans`, `brainstorming`, or any other `superpowers/*` skill
- **Do NOT run** the `using-superpowers` check between steps
- **Do NOT enter** plan mode (`EnterPlanMode`) — the HITL gates replace it
  **Exception (ADR-0017):** Express path step E1 and Hybrid path step H2 use `EnterPlanMode` as their HITL planning gate. This exception is scoped exclusively to those two steps; the prohibition applies everywhere else in all three paths.
- **Do NOT run** the `using-superpowers` check between steps
  **Exception (ADR-0017):** Express path step E1 allows the `using-superpowers` check inside plan mode. If the scope warrants `writing-plans`, `brainstorming`, or any other superpowers skill during planning, invoke it. The suppression applies to all other paths and steps.
- The **only** skills invokable inside this chain: `interview-driver`, `design-brainstorm` (gate 1b only), `macos-ux` (gate 1c only, conditional on macOS/SwiftUI SPEC detection), `claude-md-generator`, `review-triage-fix` (step 6 / H4 only, optional), `ui-layout-audit` (gate 5.05 only, conditional on UI files present), `deep-refactor` (gate 5.1 only, conditional on user choice), `commit` (step 7 / E4 / H5, always), superpowers skills (Express step E1 only, inside plan mode); `reviewer` agent with specialized inline prompts (gate 5.06 only, conditional on user choice: silent-failure-hunter scope + type-design-analyzer scope)

This section **overrides** the using-superpowers rule ("even 1% → invoke"). The chain's HITL gates manage the workflow. All intermediate skill-checks are suppressed.

---

## 1. When to invoke

**Invoke this skill when:**
- A non-trivial feature needs full design + implementation (interview → architecture → CLAUDE.md → fresh session → impl → optional review).
- You want drift-free cross-feature consistency (same dispatch template every time).
- The project does not yet have a SPEC.md and ADR for the topic.

**Three paths — Gate 0 routes every invocation (ADR-0017):**

| Path | Best for | Session | Key artifacts |
|---|---|---|---|
| **Express** | <10 files, prototype, script | Single | Manifest only |
| **Hybrid** | 5–20 files, 1–2 layers, clear requirements | Single | Manifest + SPEC.md |
| **Standard** | Complex, multi-layer, ADR required, brownfield | Fresh session | SPEC + ARCH + ADR + Plan |

Gate 0 always fires and shows all three options with an auto-detected recommendation.
All gates follow the global recommendation convention: mark the recommended option first
with " (Recommended)" label. The decision belongs to the user, not the orchestrator.

**Do NOT invoke for:**
- Hotfixes or micro-edits (use direct dispatch to `coder`).
- Iteration on an existing ADR without new interview (use `architect` dispatch manually).

---

## 2. Invocation contract

**Form A — Start new chain:**
```
/skill concept-to-code [express|hybrid|standard] <topic-full-title>
```
Examples:
- `/skill concept-to-code express Simple menu-bar utility for macOS`
- `/skill concept-to-code hybrid Rate limiter middleware for FastAPI`
- `/skill concept-to-code Rate limiter middleware for FastAPI`  ← Gate 0 shown with auto-detect

**Path prefix (optional):** if the first word is `express`, `hybrid`, or `standard`, strip it from the title, set `chain_path` immediately, and **skip Gate 0** entirely. If absent, Gate 0 fires as normal.

Behavior:
1. Parse args: if first word ∈ `{express, hybrid, standard}` → `forced_path = <word>`, `topic-full-title = remainder`. Otherwise `forced_path = null`, `topic-full-title = full args`.
2. Generate `topic-slug` from `topic-full-title` (lowercase, kebab, max 40 chars).
3. Determine `project_root` as current `$PWD`.
4. Verify `docs/manifests/` exists (create it if needed after user ack).
4. Verify no manifest exists for same topic-slug same day (if exists: error "manifest already in progress, use resume").
5. Run `scripts/gate0-detect.sh <project-root> "<topic-full-title>" "<topic-slug>"`. Read all output fields:
   `spec_adr_exist`, `mode`, `file_estimate`, `file_vote`, `keyword_vote`, `spec_topic_match`, `skill_exists`.
   (`topic-slug` is computed at step 2; passing it as arg 3 enables Bug-1 topic-match detection and the skill-exists guard.)

5b. **PROJECT.md — multi-feature project context (optional):**
   ```bash
   _project_md="<project-root>/PROJECT.md"
   ```
   - If `_project_md` exists: read its full content into `$_project_context`. Emit one line:
     `"Project context loaded from PROJECT.md — <N> phases detected."` (count `### Phase` lines).
     Store `_project_context` for injection into Steps 2 and 5.
   - If absent: `_project_context = ""`. Silent — no UX impact.

6. Invoke `scripts/manifest-init.sh` with args: `topic-slug`, `topic-full-title`, `project-root`, `<mode>` — where `<mode>` is the `mode` field from `gate0-detect.sh` output (`greenfield` or `brownfield`). **NOT** the `chain_path` (`standard`/`express`/`hybrid`) which is determined later at Gate 0.
   **Capture the manifest path from stdout** — the script prints the created path on success. Use it for all subsequent references. Example:
   ```bash
   MANIFEST=$(bash ~/.claude/skills/concept-to-code/scripts/manifest-init.sh "$slug" "$title" "$root" "$mode")
   ```
   **Never construct the manifest path manually** (e.g. `"$root/docs/manifests/$(date +%Y-%m-%d)-$slug.manifest.yml"`) — `date` at call time may differ from `date` inside the script if the chain runs across midnight.
6b. **Cost snapshot — chain start:** save a token baseline for cost tracking. Non-blocking — never fail the chain if the script is unavailable.
    ```bash
    python3 ~/.claude/scripts/usage-snapshot.py --save "chain-<topic-slug>" >/dev/null 2>&1 || true
    ```
    The snapshot label `chain-<topic-slug>` is used at the end (Step 7) to compute the cost of this chain run.
6c. **Planning placeholder `.claude/test-cmd` (ADR-0014 ext):** if `<project-root>/.claude/test-cmd` does **NOT** exist, write it with the single line `NONE`. Reason: during planning only SPEC/manifest/ADR/plan are produced (no code), but any Write marks the session "dirty" — without test-cmd the stop gate would block on planning artifacts. `NONE` is the documented opt-out for the gate. **NEVER overwrite an existing test-cmd** (a brownfield project may have a real approved one). Set `test_cmd_placeholder: true` in the manifest. Will be replaced at Gate 2 by the real command proposed by the architect (Step 2).
7. **Gate 0 — Chain routing (ADR-0017):** sets `chain_path` only. No branch here performs a
   `manifest-transition.sh` call — the chain's single routing transition out of `step_0_init`
   happens later, at Gate 0d (step 8c below).

   **Fast path (`forced_path` set from step 1):** emit `"→ chain_path: <forced_path> (explicit — Gate 0 skipped)"`, set `chain_path = forced_path` in manifest, set `gate0.auto_detect_reason = "explicit:<forced_path>"`. Proceed to step 8 below, for all three values of `forced_path` (`express`/`hybrid`/`standard`) alike.

   **Normal path (`forced_path = null`):** compute auto-detect recommendation:
   - If `spec_adr_exist=true` → force recommend **standard** (brownfield always goes full chain).
   - Otherwise majority vote: `file_vote` + `keyword_vote` + (tie-break: if file_vote=express and keyword_vote=express → express; else hybrid). Record as `auto_detect_reason` string, e.g. `"file_estimate=7,file_vote=express,keyword_vote=hybrid,spec_adr=false → hybrid"`.

   Show Gate 0 via `AskUserQuestion` (see §5 Gate 0 for full display) and wait for click.
   - `[e]` → set `chain_path: express`; proceed to step 8 below.
   - `[h]` → set `chain_path: hybrid`; proceed to step 8 below.
   - `[s]` → set `chain_path: standard`; proceed to step 8 below.
   - `[a]` → abort chain.

   Write `gate0.chain_path` and `gate0.auto_detect_reason` in the manifest via inline sed (no helper script for nested YAML yet — see §3 helper scripts note).
8. **Gate 0b (anonymize — conditional):** run `~/.claude/skills/clean-public-repo/scripts/detect-public-remote.sh <project-root>` (the script lives in the `clean-public-repo` skill, NOT in `concept-to-code/scripts/`).
   - output `silent` → Gate 0b **silent no-op**: UX unchanged, `anonymize` stays `false`. Proceed to step 8c.
   - output `public` → show Gate 0b box and wait for input:
     - `[y]` → set `manifest.anonymize = true` in the manifest (via `~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh <manifest> anonymize true`); proceed to step 8c.
     - `[n]` → `anonymize` stays `false`; proceed to step 8c.
     - `[a]` → abort chain.
   **Decision is exclusively the user's: never auto-applied.**
   (Step 8b was Gate 0c, humanize — removed per ADR-0040. Gate 0b leads straight to step 8c.)
8c. **Gate 0d (scaffolding):** see §5 Gate 0d for the full git-auto-detect / license / Xcode /
   commit survey. Gate 0d performs the chain's **single** `current_step` transition out of
   `step_0_init`: `step_0_init → gate_0d_scaffolding`, then immediately `gate_0d_scaffolding →
   step_1_interview` (`chain_path=standard`/null) or `→ step_e1_plan` (express) or `→
   step_h1_interview` (hybrid) — see `SKILL.md:1355-1358` for the exact transition block,
   unmodified by this task.

For `chain_path=standard` with `mode=brownfield`, Step 1 is a no-op (§4 Step 1 already handles
this); otherwise execution continues in the matching path's own Step 1 definition (§4 Step 1 /
Step E1 / Step H1), reached via the routing transition in step 8c above.

**Form B — Resume from manifest (use in fresh session after Step 4):**
```
/skill concept-to-code resume <manifest-path>
```
Example: `/skill concept-to-code resume /Users/stefanoferri/Developer/pricing-markup-cli/docs/manifests/2026-05-22-rate-limiter.manifest.yml`

Behavior:
1. Invoke `scripts/manifest-validate.sh <manifest-path>`. Non-zero exit → abort with parse error.
1b. **Session scope guard (IMPORTANT — runs before any other step):** read `project_root` from the manifest. Resolve the session CWD (`$PWD`). If `project_root` is NOT equal to CWD and is NOT a subdirectory of CWD, abort immediately with:
   > "SCOPE ERROR: manifest project_root (`<project_root>`) is outside this session's working directory (`<CWD>`). This session is scoped to `<CWD>` and must not operate on a different project. Open a new Claude Code session inside `<project_root>` and resume the chain from there."
   Never proceed past this guard on a scope mismatch — not even to read the manifest further.
2. Read `current_step`. Branch:
   - `ready_for_implementation` → run TOFU guard (step 2b below), then proceed to Step 5 dispatch coder.
   - Any step before `step_4_session_boundary` → error: "resume not necessary, continue in current session".
   - `completed` or `aborted` → error: "chain terminated, create a new manifest".
   - `failed` → error: "chain in failure state, manual recovery required".
3. Update `session_boundary.resumed_at` and `last_updated_at`.

**Step 2b — TOFU guard (resume path only):**

Skip entirely if `manifest.test_cmd_candidate` is null or `NONE`.

Otherwise check trust registration (read-only Bash — safe in auto mode):
```bash
TCF="<project-root>/.claude/test-cmd"
H=$(shasum -a 256 "$TCF" | awk '{print $1}')
ROOT_N=$(cd "<project-root>" && pwd -P | tr '[:upper:]' '[:lower:]')
grep -qxF "${H}	${ROOT_N}" "$HOME/.claude/state/stop-gate/trust" 2>/dev/null \
  && echo "TRUSTED" || echo "NOT_TRUSTED"
```

- `TRUSTED` → TOFU already registered; proceed to Step 5.
- `NOT_TRUSTED` → TOFU missing; present the same Gate 2b `AskUserQuestion` as the orchestrator session (§4 Gate 2b block). **NEVER call `approve-test-cmd.sh` before the "Approve" click.**
  - After "Approve": `bash ~/.claude/hooks/approve-test-cmd.sh <project-root>` — verify output contains "Approved for". Proceed to Step 5.
  - After "Skip": proceed to Step 5 (`test_cmd_provisional: true` causes stop-gate to fail-open; otherwise stop-gate will block).
  - After "Abort": terminate the chain.

**Form C — Abort chain:**
```
/skill concept-to-code abort <manifest-path>
```
Behavior: validate manifest, set `status: aborted`, set `failure.failed_at: <now>`, preserve artifacts. Idempotent.

**Manifest path convention:**
```
<project-root>/docs/manifests/YYYY-MM-DD-<topic-slug>.manifest.yml
```

---

## 3. State machine summary (v3 — schema 1.3)

Gate 0 routes every invocation to one of three sub-graphs. All share `step_0_init` as the entry point and `completed|failed|aborted` as terminal states.

**Standard path** (chain_path=standard or null — legacy):
```
step_0_init → step_1_interview → gate_1_spec_review
  → gate_1b_brainstorm_decision   (optional; direct path g1→2 preserved)
  → step_2_architecture → gate_2_architecture_review
  → step_3_project_memory → gate_3_project_memory_review
  → step_4_session_boundary → ready_for_implementation
  [FRESH SESSION]
  → step_5_implementation → step_6_review → gate_5_review_decision
  → step_7_commit → completed
  step_6_review → completed  (direct close — step_7_commit state skipped by orchestrator)
```

**Express path** (chain_path=express):
```
step_0_init → step_e1_plan → step_e2_execute → gate_e3_verify → step_e4_commit → completed
                                                             └─ completed  (Commit later / Abort)
```

**Hybrid path** (chain_path=hybrid):
```
step_0_init → step_h1_interview → gate_h1_spec_review
  → [gate_h1b_brainstorm →] step_h2_plan → step_h3_execute → gate_h3_verify
  → [step_h4_review →] step_h5_commit → completed
```

Terminal states: `completed`, `failed`, `aborted`. Any state can transition to `failed` or `aborted`.

Gates 0, 0b–0d are NOT states: they are checks run inside `step_0_init` before the first transition.

Legal transition pairs (48 total — 28 standard + 6 express + 14 hybrid, including Gate 0d routing and direct-close shortcuts):
- Standard (preserved): all 28 existing pairs unchanged
- Express (new): `step_0_init→step_e1_plan`, `step_e1_plan→step_e2_execute`, `step_e2_execute→gate_e3_verify`, `gate_e3_verify→step_e4_commit`, `step_e4_commit→completed`, `gate_e3_verify→completed`
- Hybrid (new): `step_0_init→step_h1_interview`, `step_h1_interview→gate_h1_spec_review`, `gate_h1_spec_review→step_h2_plan`, `gate_h1_spec_review→gate_h1b_brainstorm`, `gate_h1_spec_review→step_h1_interview`, `gate_h1b_brainstorm→step_h2_plan`, `gate_h1b_brainstorm→gate_h1c_macos_ux`, `gate_h1c_macos_ux→step_h2_plan`, `step_h2_plan→step_h3_execute`, `step_h3_execute→gate_h3_verify`, `gate_h3_verify→step_h4_review`, `gate_h3_verify→step_h5_commit`, `step_h4_review→step_h5_commit`, `step_h5_commit→completed`

**Resume semantics:** Express and Hybrid paths do NOT cross session boundaries. Form B resume is valid only for `chain_path=standard` or `chain_path=null` (legacy). Attempting to resume an express or hybrid manifest emits an error and aborts.

Helper scripts:

> **PATH RULE — all scripts use the absolute prefix `~/.claude/skills/concept-to-code/scripts/`.
> NEVER derive the path from the manifest location (`<manifest-dir>/scripts/` does NOT exist).
> Every bash call below must use the full absolute path.**

- `~/.claude/skills/concept-to-code/scripts/manifest-init.sh` — creates manifest at `step_0_init` (schema 1.3, adds `chain_path`, `gate0.chain_path`, `gate0.auto_detect_reason`)
- `~/.claude/skills/concept-to-code/scripts/manifest-validate.sh` — validates schema 1.0|1.1|1.2|1.3 + state invariants + optional fields
- `~/.claude/skills/clean-public-repo/scripts/detect-public-remote.sh` — auto-detect public GitHub remote (D1 ADR-0011); output `public|silent`; fail-safe to `silent`. **NB: belongs to the `clean-public-repo` skill, not to `concept-to-code` — use the absolute path.**
- `~/.claude/skills/concept-to-code/scripts/manifest-transition.sh <manifest> <new-step> [<new-status>]` — performs legal state transitions atomically (48 pairs).
  **Calling convention — 2-arg form (use for all in-chain transitions):**
  ```bash
  bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh manifest.yml gate_1_spec_review
  ```
  **3-arg form — ONLY for terminal state changes (`completed`/`failed`/`aborted`):**
  ```bash
  bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh manifest.yml completed completed
  ```
  **NEVER pass a step name as the 3rd argument** — `new_status` is the top-level `status` enum (`in_progress|failed|completed|aborted`), not `current_step`. Passing a step name (e.g. `gate_1_spec_review`) as the 3rd arg corrupts the manifest and blocks all future transitions.
- `~/.claude/skills/concept-to-code/scripts/gate0-detect.sh` — detects Gate 0 criteria (spec_adr_exist, mode)
- `~/.claude/skills/concept-to-code/scripts/manifest-set-artifact.sh <m> <key> <value>` — atomically set `artifacts.<key>` — NEW
- `~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh <m> <key> <value>` — atomically set a top-level boolean/string flag — NEW
- `~/.claude/skills/concept-to-code/scripts/manifest-set-gate.sh <m> <gate-num> <status> [notes]` — atomically set a gate's status/approved_at/notes — NEW

**IMPORTANT — never write the manifest with the Edit tool.** Use the helper scripts above
for ALL manifest mutations (transition, artifacts, gate audit). Mixing a bash write
(`manifest-transition.sh`) with an `Edit`-tool write on the same manifest triggers
recurring "file modified since read" errors. The helpers write atomically (temp + `mv`)
and bump `last_updated_at` themselves.

---

## 4. Step-by-step dispatch templates

### Step 1 — Interview (invoke `interview-driver` skill)

**Greenfield** (`mode=greenfield`, SPEC.md does not exist):
```
Use the interview-driver skill to produce SPEC.md for topic: "<topic-full-title>".
Chain context: concept-to-code (step 1).
Project root: <project-root>.
Save output to <project-root>/SPEC.md (the skill default).
Do NOT produce a closing summary or handoff message after writing SPEC.md.
Return silently — the concept-to-code orchestrator continues immediately after.
```
**CRITICAL — chain continuation (no stop):** The interview-driver Skill tool has returned.
Do NOT emit any text. Do NOT summarize. Do NOT wait for user input.
Your NEXT OUTPUT must be a Bash tool call — not a sentence, not a status line, not a handoff note.
Any text output here is a chain-stop bug. Proceed by running tools in sequence:
1. Run `bash ~/.claude/skills/concept-to-code/scripts/manifest-set-artifact.sh <manifest-path> spec <project-root>/SPEC.md`
2. **Stamp slug marker (idempotent):** run:
   ```bash
   grep -q '\*\*Topic slug:\*\*' "<project-root>/SPEC.md" || {
     cp "<project-root>/SPEC.md" "<project-root>/SPEC.md.bak" &&
     awk -v slug="<topic-slug>" '
       { print }
       !done && /^# / { print ""; print "**Topic slug:** " slug; done=1 }
     ' "<project-root>/SPEC.md" > "<project-root>/SPEC.md.tmp" &&
     mv "<project-root>/SPEC.md.tmp" "<project-root>/SPEC.md"
   }
   ```
   `awk`'s basic pattern-match/`print` semantics used here are POSIX and behave identically
   across BSD awk (macOS) and GNU/`mawk` (Ubuntu) — no OS branch needed.
3. Run `bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh <manifest-path> gate_1_spec_review`
4. Present Gate 1 (AskUserQuestion — see §5 Gate 1).

**Brownfield** (`mode=brownfield`, SPEC.md already exists):
- SKIP `interview-driver` (do not overwrite the existing SPEC).
- Set `artifacts.spec = <project-root>/SPEC.md` (the existing one).
- Transition `step_1_interview → gate_1_spec_review`.
- Present Gate 1 with note **"pre-existing spec"** (see §5 Gate 1 brownfield).

### Step 2 — Architecture (dispatch `architect` agent)

After Gate 1 approved, immediately emit: **"Gate 1 approved ✓ — preparing Gate 1b..."** (before any tool call).
Then transition `gate_1_spec_review → gate_1b_brainstorm_decision`.
Present **Gate 1b** (optional brainstorm, see §5). Then:

- **Gate 1b = `[n]`:** emit "Gate 1b: direct architecture ✓ — checking macOS detection for Gate 1c...". Then proceed to **macOS detection** (see below).
- **Gate 1b = `[y]`:** emit "Gate 1b: brainstorm active ✓ — invoking design-brainstorm...".
  1. Invoke the `design-brainstorm` skill in-session:
     ```
     Use the design-brainstorm skill.
     Chain context: concept-to-code (gate 1b).
     Requirements source: SPEC.md at <project-root>/SPEC.md.
     Explore design approaches and new application ideas with the user using structured
     ideation techniques. Write the structured brief to <project-root>/BRAINSTORM.md.
     Do NOT write SPEC, ADR, or plan. Do NOT invoke writing-plans.
     Do NOT produce a closing summary or handoff message after writing BRAINSTORM.md.
     Return silently — the concept-to-code orchestrator continues immediately after.
     ```
  **CRITICAL — chain continuation (no stop):** The design-brainstorm Skill tool has returned.
  Do NOT emit any text. Do NOT summarize. Do NOT wait for user input.
  Your NEXT OUTPUT must be a Bash tool call — not a sentence, not a status line, not a handoff note.
  Any text output here is a chain-stop bug. Proceed by running tools in sequence:
  2. Run `bash ~/.claude/skills/concept-to-code/scripts/manifest-set-artifact.sh <manifest-path> brainstorm <project-root>/BRAINSTORM.md`
  3. Then proceed immediately to **macOS detection** (see below) — next action is a Bash tool call.

**macOS detection (runs after Gate 1b regardless of [y]/[n]):**
```bash
bash ~/.claude/skills/concept-to-code/scripts/detect-macos.sh "<project-root>/SPEC.md"
```
The script strips markdown table rows and fenced/backtick code spans before grepping, avoiding false positives when SPEC.md mentions Swift/SwiftUI as keyword patterns (not as a UI target). Echoes `MACOS_DETECTED` or `NOT_MACOS`, exit 0.
- `MACOS_DETECTED` → transition `gate_1b_brainstorm_decision → gate_1c_macos_ux_decision`. Present **Gate 1c** (see §5 Gate 1c block). After Gate 1c resolves, transition `gate_1c_macos_ux_decision → step_2_architecture`.
- `NOT_MACOS` → transition `gate_1b_brainstorm_decision → step_2_architecture`. Dispatch architect (no Gate 1c shown).

**Before dispatch — inject prior notes (ADR-0012):** from the project-root run
`bash ~/.claude/skills/concept-to-code/scripts/agent-notes-harvest.sh inject architect` and
append its output to the brief below (replacing the placeholder line `PRIOR AGENT NOTES` near the end).
Stable content first → dynamic notes last preserves provider prefix-cache hits across runs.
Path resolution is the orchestrator's responsibility — never the subagent's (D2).

**Cost note (Max 20x profile):** for **routine / low-risk** ADRs, dispatch architect with override `model: sonnet` (the `model` parameter of the Agent tool); reserve **Opus** (default frontmatter) for **complex / novel / high-risk** designs. Opus resolves via `ANTHROPIC_DEFAULT_OPUS_MODEL` to `claude-opus-4-8[1m]` (fast mode: 2x standard cost, 2.5x speed). Consistent with the `opusplan` philosophy: Opus where reasoning matters, Sonnet for routine execution.

**Dispatch architect:**
```
[IF $_project_context is non-empty — add this block, otherwise omit entirely:]
## Project Roadmap (multi-feature context)
<insert full content of PROJECT.md here>
This feature is one step in the above roadmap. Design decisions (interfaces, data models, naming, patterns) must be consistent with the completed features and anticipate the planned ones listed above. Do NOT re-implement anything already marked [x].
[END IF]

Read SPEC.md at <project-root>/SPEC.md.
If a brainstorm brief exists, read it at <manifest.artifacts.brainstorm> and treat its
alternatives as candidate inputs for the ADR's "Alternatives considered" section; state
which you adopt and why.
If a UX blueprint exists, read it at <manifest.artifacts.ux_blueprint> and honor its
window/navigation/Settings/menu-bar structure decisions; reflect them in the ADR and plan.
Produce:
- ADR at <project-root>/docs/architecture/ADR-NNN-<topic-slug>.md (NNN incremental).
- Plan at <project-root>/docs/superpowers/plans/YYYY-MM-DD-<topic-slug>.md (TDD plan style, 6-10 tasks).
- Optional ARCH.md at <project-root>/ARCH.md if global architecture description needed.

Constraints:
- Auto mode active, no intermediate HITL.
- Anchor-preserving on any harness present in the project.
- Bash 3.2-clean for any helper script in plan.

[IF manifest.anonymize=true — add this block to dispatch, otherwise omit:]
Anonymize mode: ON (ADR-0011). Produce ADR and plan concisely and directly.
No meta-commentary about the tool (e.g., "generated by", AI task references, process narration).
Technical, direct docs — as a senior engineer would write them.

Return a report with: ADR path, plan path, ARCH path (or "n/a"), top 3 key decisions, top 3 risk flags.
Include TEST-CMD CANDIDATE before DURABLE NOTES (see architect.md Output Format).
End with `DURABLE NOTES:` as the absolute last block (per architect.md contract).

[IF manifest.xcode_project=true — add this block to dispatch, otherwise omit:]
XCODE PROJECT: Include a dedicated implementation task for Xcode project scaffolding (Swift 6, SwiftUI, Package.swift or .xcodeproj, directory structure, target configuration, bundle ID).

PRIOR AGENT NOTES: <orchestrator replaces this line with the output of `agent-notes-harvest.sh inject architect`: prior durable notes for architect on this project, or "none yet">
```

After architect returns, **harvest durable notes (ADR-0012)**: pipe the architect's report
via stdin to `bash ~/.claude/skills/concept-to-code/scripts/agent-notes-harvest.sh harvest architect`
(the helper extracts the terminal `DURABLE NOTES:` section and appends it to the central store
`memory/agent-notes/architect.md`, never to `MEMORY.md`; tolerates truncated reports).

**Propose `.claude/test-cmd` (ADR-0014):** extract the `TEST-CMD CANDIDATE:` block from the report. If ≠ `none`:
1. Write `<project-root>/.claude/test-cmd` with that line (it is a CANDIDATE — writing it does NOT make it trusted), **replacing the planning placeholder `NONE`** (the SHA changes → the TOFU approval below is still required).
2. Set `test_cmd_placeholder: false` in the manifest (top-level, not in artifacts).
3. Set `test_cmd_candidate: "<command>"` in the manifest (top-level).
4. If `TEST-CMD MODE: greenfield`: also set `test_cmd_provisional: true` in the manifest — the command is
   the *intent* (tests do not exist yet); until they do, consumers remain fail-open/UNVERIFIED.

If `TEST-CMD CANDIDATE: none` or absent: **leave the placeholder `NONE`** (documented opt-out — consistent with "command not inferable"; `test_cmd_placeholder` stays `true` until a real command is manually approved).

**Set coder model (CODER-MODEL CANDIDATE):** extract the `CODER-MODEL CANDIDATE:` line from the architect's report.
- `opus` (or legacy `fable` from older manifests) → set `coder_model: "opus"` in the manifest via bash sed substitution on the top-level field.
- `sonnet` or absent → set `coder_model: "sonnet"` (no dispatch override needed — global coder.md applies).

```bash
# Example sed for opus:
sed -i.bak 's/^coder_model: null$/coder_model: "opus"/' "<manifest>"
```

**Validate architect output fields (before populating artifacts):**
Parse the architect's report for these fields and act on missing ones before writing any manifest entry:

| Field | How to detect | On missing |
|---|---|---|
| ADR path | Line containing `docs/architecture/ADR-` | **HARD ABORT** |
| Plan path | Line containing `docs/superpowers/plans/` | **HARD ABORT** |
| `TEST-CMD CANDIDATE:` | Line starting with that literal | Warn + leave `NONE` placeholder |
| `CODER-MODEL CANDIDATE:` | Line starting with that literal | Warn + default to `sonnet` |
| `DURABLE NOTES:` | Terminal block present | Warn: "durable notes absent — architect may have truncated" |

On **HARD ABORT** (ADR path or plan path missing): do NOT populate `manifest.artifacts`, do NOT transition to `gate_2_architecture_review`. Present to user:
> "Architect report is missing critical output fields (ADR path or plan path). The architect may have truncated mid-run. Verify the session transcript, then re-dispatch architect or restore the missing artifacts manually before proceeding."

Then populate `manifest.artifacts.{adr, plan, arch}`. Transition to `gate_2_architecture_review`.
**Present Gate 2 to user via `AskUserQuestion`** (see Gate 2 block below).

**TOFU rules — invariant:**
- **NEVER call `approve-test-cmd.sh` before the user's explicit click on Gate 2b.**
- **NEVER modify `.claude/test-cmd` autonomously** after Gate 2 (not for error correction, not for updates). Any change requires a new `AskUserQuestion` with the new command and re-approval.
- Only after the "Approve" click on Gate 2b: `bash ~/.claude/hooks/approve-test-cmd.sh <project-root>` — verify the output contains "Approved for".
- Trust is born ONLY from explicit human SHA-pinned consent. The system never auto-trusts.

### Step 3 — Project memory

**Two branches depending on whether `<project-root>/CLAUDE.md` already exists:**

---

**Branch A — CLAUDE.md EXISTS (brownfield append — orchestrator appends directly):**

The orchestrator handles the append without dispatching `claude-md-generator`. Rationale: the generator is designed to produce a CLAUDE.md from scratch (template selection); using it to append 20 lines to an existing, carefully-curated CLAUDE.md is out of its designed context and risks introducing template artefacts.

Steps:
1. Read the ADR path from `manifest.artifacts.adr` and the ADR content to extract key architectural decisions.
2. Compose the new section in the same format as the existing `## Decisions from the <x> chain (ADR-NNN)` blocks:
   ```markdown
   ## Decisions from the <topic-full-title> chain (<ADR-NNN>)

   <skill-or-feature description, one sentence>: `<invocation or path>`.

   Key architectural decisions:
   - **<Decision 1 label>:** <one-line summary>
   - **<Decision 2 label>:** <one-line summary>
   [... 4-8 bullets total ...]

   Detail: `<relative path to ADR file>`.
   ```
3. Write `<project-root>/CLAUDE.md.proposed`: copy of CLAUDE.md with the new section appended.
4. **Line-count guard (Feature 5):** run `wc -l < CLAUDE.md.proposed`. If the count exceeds 180, prepend to the Gate 3 question:
   `"⚠ CLAUDE.md.proposed is <N> lines (blueprint target <200). Consider running /skill claude-md-slim on this file after implementation to extract path-scoped rules.\n\n"`
5. Transition to `gate_3_project_memory_review`. Display only the added lines (`diff CLAUDE.md CLAUDE.md.proposed`) as text, then present Gate 3 (see §5 Gate 3 block).

---

**Branch B — CLAUDE.md does NOT exist (greenfield — invoke `claude-md-generator` skill):**

**IMPORTANT — use the `Skill` tool, NOT the `Agent` tool.** `claude-md-generator` is a
**skill** (not an agent): invoke via `Skill(skill="claude-md-generator", args="...")`,
never via `Agent(subagent_type="claude-md-generator")` (which would give "agent not found").

```
Use the claude-md-generator skill (invoke via Skill tool, not Agent tool).
Read SPEC.md at <project-root>/SPEC.md and ARCH.md at <project-root>/ARCH.md
(if exists, else use ADR at <manifest.artifacts.adr>).

Generate CLAUDE.md.proposed from scratch at <project-root>/CLAUDE.md.proposed.
Do NOT overwrite <project-root>/CLAUDE.md — only write the .proposed file.

After writing CLAUDE.md.proposed, within this SAME turn (do NOT end the turn first):
- Transition to `gate_3_project_memory_review`.
- Display full proposed content (max 100 lines) as text.
Then IMMEDIATELY call AskUserQuestion with the Gate 3 block (see §5 Gate 3).
```

On Gate 3 approve: emit "Gate 3 approved ✓ — applying CLAUDE.md and proceeding to Gate 4...". Then `mv CLAUDE.md.proposed CLAUDE.md`. Transition to `step_4_session_boundary`. Present Gate 4.

### Step 5 — Implementation (dispatch `coder` agent, post-resume)

**Dispatch mode selection:**
- If `manifest.hook_verified = true`: use Workflow dispatch path (below).
- If `manifest.hook_verified = false` or `null` (field absent): present smoke test gate (see
  "Smoke test gate" block below) and STOP until user records result.
- If Dynamic Workflows is unavailable or the `ultracode` keyword (renamed from `workflow` in CC v2.1.160) does not trigger script generation:
  fall back to Agent-tool batch dispatch (see "Fallback — Agent-tool batch dispatch" below).
  Set `step5_mode: "agent_batch"` via bash sed substitution (same as the fallback section below).

**Pre-dispatch: worktree isolation check (run ONCE before any dispatch):**
```bash
git rev-parse --git-dir 2>/dev/null
```
The worktree is created from the CWD of the session, not from `project_root` — check the CWD,
not `project_root`. If the CWD is not inside a git repo the worktree will fail even if
`project_root` has its own `.git`.
- exit 0 → CWD is inside a git repo → dispatch coder **with** `isolation: worktree` (default).
- exit non-0 → CWD is not a git repo (session started from a parent directory, monorepo, etc.) →
  dispatch coder **with** `isolation: "none"` (explicit override in the `isolation` parameter
  of the `Agent` tool). **Do not re-dispatch with worktree: it will fail again.**
  Note in the report: "worktree disabled — session CWD not inside a git repo".

**Pre-dispatch: artifact existence check (run before any dispatch):**
```bash
test -f "<manifest.artifacts.adr>"  || echo "MISSING_ADR"
test -f "<manifest.artifacts.plan>" || echo "MISSING_PLAN"
```
If either path is missing on disk: do NOT dispatch coder. Present to user:
> "Artifact not found: `<missing path>`. Architect may have truncated before writing the file. Re-run architect dispatch (Step 2) or restore the file manually."

**Pre-dispatch: plan structure validation (run after existence check):**
```bash
unchecked=$(grep -c '- \[ \]' "<manifest.artifacts.plan>" 2>/dev/null || echo 0)
```
If `unchecked = 0`: do NOT dispatch coder. Present to user:
> "Plan at `<manifest.artifacts.plan>` has no unchecked tasks (`- [ ]`). Architect may have marked all tasks done, or the plan is malformed. Open the plan, verify the task list, and re-invoke Step 5."

#### Smoke test gate (pre-dispatch, blocks if hook_verified = false)

If `manifest.hook_verified = false` or `null` or the field is absent from the manifest:

Run the deterministic check. Do NOT ask the user to watch the terminal: a hook that never fired and a
hook that fired and stood down look identical on screen. `pre-flight-pattern-enforce.sh` records every
decision it makes to its own audit log, and that log is the evidence.

**Step A — mark, and make a scratch file:**
```bash
MARK=$(bash ~/.claude/skills/concept-to-code/scripts/hook-verify-workflow.sh --mark)
SMOKE_DIR=$(mktemp -d); printf 'hello\n' > "$SMOKE_DIR/test.txt"
```

**Step B — dispatch exactly one workflow agent, spawned as a coder.** Send this prompt:
```
ultracode — use a workflow with exactly one agent, spawned with agentType: 'coder',
to append the line 'smoke test ok' to <SMOKE_DIR>/test.txt.
```
The `agentType: 'coder'` is load-bearing. A default workflow subagent reports
`agent_type=workflow-subagent`, and the guard bypasses on its agent_type check without enforcing.

**Step C — check:**
```bash
bash ~/.claude/skills/concept-to-code/scripts/hook-verify-workflow.sh --check "$MARK"
```

Record by exit code:
- **exit 0 (VERIFIED)** → `bash ~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh <manifest> hook_verified true`
  (the helper supports any top-level unquoted boolean key). Proceed to the Workflow dispatch path.
- **exit 1 (REFUTED)** → `bash ~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh <manifest> hook_verified false`.
  Proceed to Fallback (Agent-tool batch dispatch). The printed reason names which failure occurred:
  no decision recorded after the marker (hooks disabled, or the workflow never dispatched), every
  workflow agent reported `workflow-subagent` (the dispatch omitted `agentType: 'coder'` — a
  workflow-script bug, not a platform limitation), or every decision after the marker belongs to a different, concurrent Claude Code session
  (`CLAUDE_CODE_SESSION_ID` was set and filtered them out — issue #33).
- **exit 3 (INCONCLUSIVE)** → record NOTHING, do not call `manifest-set-flag.sh`. Either the audit log
  is missing (`pre-flight-pattern-enforce.sh` is not installed — fix the install, then re-run), or
  `CLAUDE_CODE_SESSION_ID` was unavailable and the post-marker window mixed rows from more than one
  concurrent Claude Code session, so the check cannot tell which one is this session's (re-run when no
  other session is active, or on a CLI version that sets `CLAUDE_CODE_SESSION_ID` — issue #33). The
  printed `reason=` line names which of the two applies. **Never record `false` on exit 3.** Neither
  cause is evidence that hooks fail to fire.

Do not run the check while another coder agent is working in this session: the audit log does not
distinguish a workflow coder from an Agent-tool coder.

IMPORTANT: if `hook_verified = false`, the workflow path is blocked and the chain uses the Agent-tool
batch dispatch (fallback).

The gate fires ONCE per manifest. After `hook_verified` is recorded, the gate is silent for
all subsequent Step 5 runs on the same manifest.

**[Autopilot default (`manifest.autopilot = true`): do NOT display the smoke-test procedure and do NOT
wait for a human. If `hook_verified` is `true`, take the Workflow path; otherwise record
`hook_verified = false` via `manifest-set-flag.sh` and take the Agent-tool fallback. Emit:
"Step 5: autopilot — workflow smoke test skipped, using <workflow|fallback> ✓". This prevents an
unattended run from stalling on the smoke-test prompt, and never takes the Workflow path unless hooks
were already verified true.]**

#### Workflow dispatch path (hook_verified = true)

**CONSTRAINT — NO inline source code in the generated workflow script:**
Agent prompt strings in the JS workflow script MUST reference files by path only — never inline raw source code blocks. Embedding language-specific generics (e.g. `Array<T>`, `Result<T, E>`) or type annotations directly in JS template literals triggers a parse error (`Unexpected token`). If context requires a code snippet, write it to a temp file and pass the path to the agent.

**Before dispatch — parallel task conflict scan (GAP E):**
Read the plan at `<manifest.artifacts.plan>`. Scan each task description for explicit file-path mentions (lines containing `/` paths or filenames with extensions). If the same file path appears in multiple task descriptions, emit a warning before dispatching:
> "File conflict risk: `<path>` appears in tasks <N> and <M>. Parallel coders may conflict during worktree merge. Consider batching these tasks sequentially."
This is advisory only — not a hard gate. The user may proceed; the warning surfaces the risk.

Step 5 dispatch prompt (send as a single message to the session):
```
ultracode — use a workflow to dispatch the following coder tasks in parallel.
IMPORTANT: The workflow script must be deterministic — do NOT use Date.now(), new Date(), or Math.random(). These calls throw at runtime and break workflow resume (CC 2.1.172 removed the validation warning but the runtime constraint remains).
Read plan at <manifest.artifacts.plan>.
Read ADR at <manifest.artifacts.adr>.
Read SPEC.md at <manifest.artifacts.spec>.
Read project CLAUDE.md at <manifest.artifacts.project_claude_md> (if not null).

[IF $_project_context is non-empty — add this block, otherwise omit entirely:]
## Project Roadmap (multi-feature context)
<insert full content of PROJECT.md here>
Implement ONLY what is specified in the plan above. Do NOT implement features marked [ ] (planned but not yet started) or re-implement anything marked [x] (already done). Use the roadmap only to understand existing interfaces, naming, and patterns you must stay consistent with.
[END IF]

Dispatch one coder subagent per task group. Use your Pre-flight Pattern Classifier
(ADR-0001) for every Edit operation. Auto mode active. No intermediate HITL.
`.claude/test-cmd` is off-limits — never read, write, or modify it. If the test command needs changing, stop and report it to the orchestrator.

**Pin the model explicitly on every agent() call (no CLI-model inheritance):** in the
Workflow path a subagent dispatched with `agentType` but **no** `model` inherits the main-loop
(CLI session) model, NOT the agent's frontmatter. To keep the chain on its configured models
regardless of which model the orchestrator session runs, ALWAYS pass an explicit `model`:
- `manifest.coder_model = "opus"` (or legacy `"fable"`) → `agent(prompt, { agentType: "coder", model: "opus", ... })`.
- `manifest.coder_model = "sonnet"` or null → `agent(prompt, { agentType: "coder", model: "sonnet", ... })` (still explicit — do NOT omit `model`, or the coder would inherit the CLI model).

**Pin `effort` explicitly too, for the same reason.** The Workflow tool documents `opts.effort` as
"omit to inherit the session effort", so an omitted `effort` behaves exactly like an omitted
`model`: the subagent takes the orchestrator session's value instead of the one pinned in its own
frontmatter. Raising the orchestrator's `effortLevel` would then silently raise every dispatched
agent with it, which is both a cost increase nobody asked for and a loss of the per-agent
calibration. Pass the agent's own frontmatter value on every `agent()` call:

| agentType | effort |
| --- | --- |
| `architect` | `xhigh` |
| `coder`, `reviewer`, `debugger` | `high` |
| `tester`, `refactorer` | `medium` |
| `doc-writer`, `researcher` | `low` |

If an agent's frontmatter changes, this table is the second place to update — they are not
linked, and a mismatch here silently overrides the file.

[IF manifest.step5_review_mode = checkpoint — add this block to dispatch, otherwise omit entirely:]
Checkpoint review: ON (ADR-0039 D5-D9).
Build the script with pipeline(), one entry per task, two stages: implement, then review.
Do NOT use parallel() as a barrier between the stages — task B must keep implementing while
task A is under review. Wall-clock is the slowest single-task chain, not sum-of-slowest-per-stage.
Stage 2 dispatches agentType "reviewer" scoped to the files stage 1 reported for that task.
Pass an explicit model AND an explicit effort of "high" (same rules as the coder above).
It REVIEWS ONLY and fixes nothing.
Pass each task's BLOCKER and MAJOR findings into the prompt of the next task's stage 1 as
"found in task <N>, do not repeat this". MINOR and NIT are recorded and left for Step 6.
Collect every review into the checkpoint_reviews array of step5-report.json.
[END IF]

After all tasks complete, the final subagent MUST write
<project_root>/.claude/step5-report.json with the schema defined in the
step5-report.json contract section (schema: see ~/.claude/skills/concept-to-code/SKILL.md §4 Step 5 contract).

[IF manifest.anonymize=true — add this block to dispatch, otherwise omit:]
Anonymize mode: ON (ADR-0011).
- Commit messages in Conventional Commits: minimal subject + body. No tool trailers
  (e.g., "Co-Authored-By: Claude", "Generated with Claude Code") — already off via
  settings.json, reiterated here.
- No trace comments in code: no "// added by Claude", AI/task references, generated TODOs.
  Only comments a human author would write.
- No file slop: only files required by the plan (no redundant READMEs, scratch files, notes).
- No decorative emoji unless requested. Concise and technical docs.
```

After the workflow completes:
1. Read `<project_root>/.claude/step5-report.json`.
2. If the file is absent → fall back to `git diff + test run` directly (do NOT re-dispatch).
3. If `tasks_failed` is non-empty OR `test_result` is `red` → failure signal. Present to
   user; do NOT transition to `step_6_review` without user acknowledgment.
4. If all tasks passed and `test_result` is `green` or `n/a` → transition to `step_6_review`.
   Present Gate 5.

Set `step5_mode: "workflow"` in the manifest (via bash sed substitution on the additive
field — NOT via Edit tool).

#### step5-report.json schema and orchestrator read contract

The final workflow subagent writes this file to `<project_root>/.claude/step5-report.json`.
The orchestrator reads it after the workflow exits.

Schema (JSON):
```json
{
  "step5_mode": "workflow",
  "tasks_completed": [1, 2, 3],
  "tasks_failed": [],
  "files_modified": [
    { "path": "<absolute path>", "operation": "edit|create|delete" }
  ],
  "test_result": "green | red | n/a",
  "test_output_tail": "<last 20 lines of test output or empty string>",
  "harness_deltas": "PASS=N FAIL=0 (delta from baseline, or n/a)",
  "checkpoint_reviews": [
    { "task": 1,
      "severity_counts": { "BLOCKER": 0, "MAJOR": 1, "MINOR": 2, "NIT": 0 },
      "blocking_findings": ["<one line per BLOCKER/MAJOR, passed to the next task>"] }
  ],
  "errors": []
}
```

`checkpoint_reviews` is an empty array when `step5_review_mode` is `none` (the default), which
is also what every manifest written before ADR-0039 means by omitting the field.

**Orchestrator read contract:**
- Stale detection: check file modification time via `stat -f %m <file>` against
  `manifest.last_updated_at` epoch. If the file is older, it is stale (from a prior run).
  Ignore it and use `git diff + test run` directly.
- `tasks_failed` non-empty → failure signal.
- `test_result: "red"` → failure signal.
- Failure signal behavior: present to user, do NOT auto-transition to `step_6_review`.
- `step5-report.json` absent → git diff + test run directly (not a blocking error).
- Schema validation: check that `step5_mode` and `tasks_completed` are present.
  If either is missing, treat the file as malformed → git diff fallback.
- `checkpoint_reviews` is **never** a failure signal. Its findings were already fed forward to
  the next task during Step 5; they do not block the transition to `step_6_review`, where the
  full RTF cycle sees them anyway. A missing `checkpoint_reviews` key is not malformed — it is
  what a `step5_review_mode: none` run produces.

#### Fallback — Agent-tool batch dispatch (hook_verified = false or workflow unavailable)

**Batch-dispatch policy (≥6 tasks in plan):** if the plan contains ≥6 tasks, do NOT
dispatch the coder as a single monolithic block — the dispatch can silently truncate
halfway (context overflow, timeout) without a final report and without running the
closing gates. Split the dispatch into **batches of 2-3 tasks**:

1. Dispatch coder with batch 1 (tasks 1-N, where N ≤ 3).
2. Checkpoint between batches: run `verify.sh <root>` and check `git status` yourself
   as the orchestrator — do NOT trust the coder's report to decide whether to continue
   (it may be truncated or incomplete).

   **[IF `manifest.step5_review_mode = checkpoint` (ADR-0039 D5-D9) — otherwise skip:]**
   At this same checkpoint, dispatch the `reviewer` agent scoped to the diff of the batch that
   just closed. It reviews only and fixes nothing: this is where the Workflow path would run its
   pipeline review stage, and the two paths must reach the same place. Carry the BLOCKER and
   MAJOR findings into the brief of the next batch as "found in batch <N>, do not repeat this".
   MINOR and NIT are recorded and left for Step 6, where RTF runs the full cycle over the whole
   diff. Record each review in `checkpoint_reviews` in `step5-report.json`.
   A finding here never halts the chain — it is feedback for the next batch, not a gate.
   If a dispatch returns without output or hangs unexpectedly, run:
   `claude agents --json | jq '.[] | select(.waitingFor != null) | {id, waitingFor}'`
   A non-null `waitingFor` means the coder is blocked on a permission prompt —
   surface it to the user rather than waiting in silence (CC 2.1.162+).
3. Dispatch coder with batch 2 (tasks N+1…), and so on.
4. After the last batch: final verification (`verify.sh`, `git status`, scope check
   against the plan) before transitioning to `step_6_review`.

For plans with ≤5 tasks monolithic dispatch is acceptable, but the controller-side
verification after dispatch is mandatory in all cases.

**Coder model override:** if `manifest.coder_model = "opus"` (or legacy `"fable"`), pass `model: "opus"` to every `Agent(subagent_type="coder", ...)` call in this dispatch. If `sonnet` or null, omit the `model` parameter (global coder.md applies).

**Single batch dispatch template:**
```
Read plan at <manifest.artifacts.plan> (tasks <FROM>-<TO> only).
Read ADR at <manifest.artifacts.adr>.
Read SPEC.md at <manifest.artifacts.spec>.
Read project CLAUDE.md at <manifest.artifacts.project_claude_md> (if not null).

Execute tasks <FROM>-<TO> of the plan following TDD (red → green → checkpoint).
Use your Pre-flight Pattern Classifier (ADR-0001) for every Edit operation.

Auto mode active. No intermediate HITL.
`.claude/test-cmd` is off-limits — never read, write, or modify it. If the test command needs changing, stop and report it to the orchestrator.

[IF manifest.license != null AND manifest.license != "None" — add this line to dispatch, otherwise omit:]
LICENSE FILE: Ensure a LICENSE file exists at the project root matching the declared license (<manifest.license>). Create it if absent; do not modify if present.

[IF manifest.xcode_project=true — add this line to dispatch, otherwise omit:]
XCODE SCAFFOLD: Execute the Xcode project scaffold task from the plan (Swift 6, SwiftUI structure, Package.swift or .xcodeproj, target config, bundle ID) as part of this batch if included in tasks <FROM>-<TO>.

[IF manifest.anonymize=true — add this block to dispatch, otherwise omit:]
Anonymize mode: ON (ADR-0011).
- Commit messages in Conventional Commits: minimal subject + body. No tool trailers
  (e.g., "Co-Authored-By: Claude", "Generated with Claude Code") — already off via
  settings.json, reiterated here.
- No trace comments in code: no "// added by Claude", AI/task references, generated TODOs.
  Only comments a human author would write.
- No file slop: only files required by the plan (no redundant READMEs, scratch files, notes).
- No decorative emoji unless requested. Concise and technical docs.

Return a report with: tasks completed (list), files modified, test results, harness deltas.
End the report with exactly this line (no trailing text): `PATTERN: DONE tasks=<N> files=<M>`
where N = number of tasks completed and M = number of files modified.
```

After each batch, before running controller-side verification:
- Check the agent report text for `PATTERN: DONE` on its own line.
- If absent: the dispatch was likely truncated (socket close / context overflow). Do NOT continue to the next batch or transition. Present to the user: "Coder dispatch may have been truncated — PATTERN: DONE not found in report. Verify `git diff` manually before proceeding." Wait for user acknowledgment.
- If present: proceed with controller-side verification as normal.

After all batches complete and controller-side verification passes, transition to
`step_6_review`. Present Gate 5.

Set `step5_mode: "agent_batch"` in the manifest when the fallback activates (via bash sed substitution on the additive field — NOT via Edit tool, NOT via manifest-set-flag.sh which is boolean-only).

### Step 6 — Review cycle (conditional on hook_verified)

**Dispatch mode selection:**
- If `manifest.hook_verified = true`: use Workflow dispatch path (below). Set `step6_mode: "workflow"` via bash sed substitution.
- If `manifest.hook_verified = false` or `null`: use skill fallback (below). Set `step6_mode: "skill_fallback"` via bash sed substitution.

#### Workflow dispatch path (hook_verified = true)

Send the following workflow prompt to the session:

```
ultracode — use a workflow to run a parallel review-and-fix cycle.
IMPORTANT: The workflow script must be deterministic — do NOT use Date.now(), new Date(), or Math.random(). These calls throw at runtime and break workflow resume (CC 2.1.172 removed the validation warning but the runtime constraint remains).
IMPORTANT: every agent() call pins its model explicitly (reviewer → sonnet, fix agents → opus). A workflow subagent with agentType but no model inherits the main-loop (CLI session) model, not the agent frontmatter — so omit nothing.

FINDINGS_SCHEMA (each finding object):
{
  "id": "<sev>-<file_basename>-<hash3>",
  "severity": "P1 | P2 | P3",
  "category": "bug | security | perf | style",
  "file": "<absolute path>",
  "line": <integer or null>,
  "description": "<concise problem statement>",
  "fix_type": "debugger | refactorer | coder"
}

Phase 1 — Review:
  agent({ agentType: "reviewer", model: "sonnet" }, `
    Review all files modified in this implementation cycle.
    Return a JSON array of findings matching FINDINGS_SCHEMA.
    Key: "findings". No other top-level keys.
  `)

Phase 2 — Group findings by file (in-script, no agent):
  const findings = JSON.parse(reviewResult).findings ?? [];
  const byFile = {};
  for (const f of findings) {
    if (!byFile[f.file]) byFile[f.file] = [];
    byFile[f.file].push(f);
  }
  const fileGroups = Object.values(byFile);

Phase 3 — Fix in parallel per file group:
  await parallel(fileGroups.map(group => () =>
    agent({ agentType: group[0].fix_type, model: "opus" }, `
      Fix the following findings in ${group[0].file}:
      ${JSON.stringify(group, null, 2)}
      Use Pre-flight Pattern Classifier (ADR-0001) for every Edit.
      Return: { "fixed": [<id>, ...], "skipped": [<id>, ...], "notes": "<string>" }
    `)
  ));

Phase 4 — Re-review:
  agent({ agentType: "reviewer", model: "sonnet" }, `
    Re-review all files that were fixed in Phase 3.
    Confirm each finding from Phase 1 is resolved or document why it was skipped.
    Return: { "resolved": [<id>, ...], "remaining": [<id>, ...], "summary": "<string>" }
  `)

Final subagent writes <project_root>/.claude/step6-report.json:
{
  "step6_mode": "workflow",
  "findings_count": <n>,
  "resolved_count": <n>,
  "remaining_count": <n>,
  "remaining_ids": [...],
  "summary": "<string>"
}
```

After the workflow completes:
1. Read `<project_root>/.claude/step6-report.json`.
2. If absent or malformed → fall back to skill fallback below (record `step6_mode: "skill_fallback"`).
3. If `remaining_count > 0` → present unresolved findings to user before transitioning.
4. Evaluate Gate 5.05 (see §5 Gate 5.05 block).

#### Skill fallback (hook_verified = false or workflow unavailable)

```
Use the review-triage-fix skill.
Target: files modified by coder in step_5_implementation (see manifest.artifacts.plan completion section).
Execute review-triage-fix v1.2 with Add+Remove rule.

Return final report.
```

After review (or skip), evaluate Gate 5.05 (see §5 Gate 5.05 block).

### Step 7 — Commit (invoke `commit` skill, always)

**IMPORTANT — use the `Skill` tool, NOT the `Agent` tool.** `commit` is a **skill**, not an agent.

```
Use the commit skill (invoke via Skill tool, not Agent tool).
Context hint: "<topic-full-title> (ADR: <manifest.artifacts.adr>)"
```

The skill manages the HITL gate (AskUserQuestion), Conventional Commits message generation, and the PR option internally. The orchestrator does nothing after invocation: the skill closes the cycle on its own.

**Post-commit push (conditional on `manifest.initial_commit_push = "push" AND manifest.autopilot != true`):**

This block is skipped unconditionally when `autopilot = true` — `concept-to-code`'s own autopilot
mode never pushes unattended (ADR-0020 D2). No separately-orchestrated automated publish flow is
threaded through here: any such flow runs entirely outside this block, through
`project-conductor`'s `publish-feature.sh`, strictly after this chain hands back a local commit
(ADR-0022 D5/D6) — this file stays agnostic to that outer orchestration by design.

After the commit skill completes successfully, if `manifest.initial_commit_push = "push" AND manifest.autopilot != true`:

1. Resolve remote URL from `manifest.git_remote_url`. If null, prompt user:
   ```
   Gate 7 · Push — remote URL not set. Provide the remote URL now, or type "skip" to abort push.
   ```
2. If URL is available:
   ```bash
   git -C <project_root> remote get-url origin 2>/dev/null || \
     git -C <project_root> remote add origin <git_remote_url>
   ```
3. **New-repo guard (only when `git_init: true`)** — check if the remote is empty:
   ```bash
   git -C <project_root> ls-remote --heads origin 2>/dev/null
   ```
   - **Empty output (brand-new remote, no branches):** push `HEAD` directly as `main` to establish it as the default branch:
     ```bash
     git -C <project_root> push -u origin HEAD:main
     ```
     Report: "Pushed initial bootstrap directly to `main` on `<git_remote_url>`." **Do NOT create a PR** — this IS the initial content of `main`; there is nothing to merge.
   - **Non-empty (existing branches):** push feature branch normally and proceed with PR:
     ```bash
     git -C <project_root> push -u origin HEAD
     ```
4. If push succeeds (either path): report branch pushed and URL.
5. If push fails: report the error to user. Do NOT abort the chain — the commit already succeeded. Suggest manual push: `git push -u origin HEAD` (or `HEAD:main` for new repos).

**Post-commit PROJECT.md update (conditional on `$_project_context` non-empty):**

If PROJECT.md was loaded at Gate 0 AND the commit skill completed successfully (not aborted):

**[Autopilot default: auto-update PROJECT.md (no AskUserQuestion). Emit: "PROJECT.md: autopilot — feature marked [x] ✓". Apply sed substitution and proceed.]**

Use `AskUserQuestion` (only when `manifest.autopilot = false`):
```
question: "Update PROJECT.md — mark '<topic-full-title>' as completed? (Human approval required)\n\nThis will change the matching '- [ ] ...' line to '- [x] ... (completed: <YYYY-MM-DD>)' in <project-root>/PROJECT.md."
header: "PROJECT.md · Update"
options:
  - label: "Yes — mark completed"
    description: "Updates the matching line in PROJECT.md in-place"
  - label: "Skip"
    description: "Leave PROJECT.md unchanged"
```
If "Yes": find the line in PROJECT.md matching `<topic-full-title>` (fuzzy: normalize to lowercase, ignore leading `- [ ] `) and replace `- [ ]` with `- [x]`, appending `(completed: <YYYY-MM-DD>)`. Use bash to perform the substitution (NOT Edit tool). Emit: `"PROJECT.md updated ✓"`
If "Skip": silent.

After commit skill completes (whether commit was made or aborted by user):

**Cost snapshot — chain end:** compute and print the spend for this chain run.
```bash
python3 ~/.claude/scripts/usage-snapshot.py --diff "chain-<topic-slug>" --log-to ~/.claude/chain-eval.md 2>/dev/null || true
```
Emit the diff output inline in the final report. If the snapshot file is missing (e.g. chain was resumed mid-run), skip silently.

Transition to `completed`. Write final report.

---

### Express path — Steps E1–E4 (chain_path=express)

No sub-agents. No fresh session. No SPEC, ARCH, or ADR. The orchestrator executes everything directly.

**No worktree isolation** — failures during E2 leave partial edits in the working tree. The user must `git status` and reset manually if needed. Known limitation (ADR-0017).

#### Step E1 — Plan (EnterPlanMode + superpowers allowed)

Immediately after Gate 0d routes to `step_e1_plan`:

1. Run the `using-superpowers` check. If a superpowers skill applies (`writing-plans`, `brainstorming`, etc.), invoke it now before entering plan mode.
2. Emit: "Express path active — entering plan mode..."
3. Call `EnterPlanMode`. The plan approval UI is the E1 HITL gate (no separate AskUserQuestion).
4. Read relevant project files to understand the scope.
5. Propose a 3–6 task plan covering all work. Each task: goal, files to change, test to run (if any).
6. Wait for user approval in plan mode.
7. On approval: call `ExitPlanMode`, emit "Plan approved — executing...", then run:
   ```bash
   bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh <manifest-path> step_e2_execute
   ```

#### Step E2 — Execute

**Uncommitted-changes guard (before any Edit/Write on source files):**
```bash
git -C <project_root> status --short 2>/dev/null
```
If output is non-empty, present `AskUserQuestion` before touching any file:
- `Commit first (Recommended)` — stop here; commit existing changes, then re-invoke the chain.
- `Proceed anyway` — plan edits will mix with existing uncommitted changes; emit a warning line before starting.
- `Abort` — exit with no writes.

Execute the approved plan directly with Edit/Write/Bash tool calls. No sub-agents.
After completing each plan task, emit a one-line progress update before starting the next:
`"Task N/M — <brief description>: done."`

After all plan tasks are complete:
- Run the project test command if `test_cmd != NONE` and test_cmd exists.
- Run:
  ```bash
  bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh <manifest-path> gate_e3_verify
  ```
- Present Gate E3.

#### Gate E3 — Verify and commit (AskUserQuestion)

```
question: "Gate E3 — Express path complete\n\nFiles modified: <list>\nTest result: <PASS/FAIL/skipped>\n\nChoose next action:"
header: "Gate E3 · Verify"
options:
  - label: "Commit now"
    description: "Invoke the commit skill immediately."
  - label: "Commit later"
    description: "Leave changes staged; user will commit manually."
  - label: "Abort"
    description: "Stop here. Changes remain in the working tree."
```

`Commit now`:
```bash
bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh <manifest-path> step_e4_commit
```
Then proceed to Step E4.

`Commit later`:
```bash
bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh <manifest-path> completed completed
```
No commit skill invoked. Implementation is complete; the user will commit manually later.

`Abort`:
```bash
bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh <manifest-path> aborted aborted
```
No commit skill invoked. Matches the option's own description ("Stop here. Changes remain in the
working tree.") — an abandonment, not a completion.

#### Step E4 — Commit

Invoke `commit` skill (Skill tool, not Agent). After the commit skill returns:
```bash
bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh <manifest-path> completed completed
```

---

### Hybrid path — Steps H1–H5 (chain_path=hybrid)

No sub-agents. No fresh session. Produces SPEC.md only — no ARCH, no ADR, no architect agent. Plan mode replaces the architect step. The orchestrator executes implementation directly.

**Context window limit: 20 files.** Above this, context compaction during H3 may lose the plan. Use the standard path for projects above this size.

#### Step H1 — Interview (invoke `interview-driver` skill)

Identical to standard Step 1. Invoke `interview-driver` skill, produce SPEC.md. Use this invocation:
```
Use the interview-driver skill to produce SPEC.md for topic: "<topic-full-title>".
Chain context: concept-to-code (step H1, hybrid path).
Project root: <project-root>.
Save output to <project-root>/SPEC.md (the skill default).
Do NOT produce a closing summary or handoff message after writing SPEC.md.
Return silently — the concept-to-code orchestrator continues immediately after.
```
**CRITICAL — chain continuation (no stop):** After the interview-driver Skill tool returns,
do NOT produce any text response and do NOT wait for user input. Proceed IMMEDIATELY to:
1. Update manifest: `artifacts.spec = <project-root>/SPEC.md` via bash sed.
2. Transition `step_0_init → step_h1_interview` then `step_h1_interview → gate_h1_spec_review`.
3. Present Gate H1.

#### Gate H1 — Spec review

Identical to standard Gate 1 (see §5 Gate 1). On approve: transition to `gate_h1b_brainstorm` (show Gate H1b). On reject: re-invoke `interview-driver`.

#### Gate H1b — Brainstorm decision (optional)

Identical to standard Gate 1b (see §5 Gate 1b). On `[y]`: invoke `design-brainstorm`, write BRAINSTORM.md, set `artifacts.brainstorm`. On `[n]`: proceed without brief. After Gate H1b (both branches), run macOS detection (same script as standard path):
```bash
bash ~/.claude/skills/concept-to-code/scripts/detect-macos.sh "<project-root>/SPEC.md"
```
- `MACOS_DETECTED` → transition `gate_h1b_brainstorm → gate_h1c_macos_ux`, show **Gate H1c** (see below). After Gate H1c resolves, transition `gate_h1c_macos_ux → step_h2_plan`.
- `NOT_MACOS` → transition `gate_h1b_brainstorm → step_h2_plan` directly.

#### Gate H1c — macOS UX design (optional, conditional)

Identical to standard Gate 1c (see §5 Gate 1c block). On `[y]`: invoke `macos-ux` design, write UX-BLUEPRINT.md, set `artifacts.ux_blueprint`, transition `gate_h1c_macos_ux → step_h2_plan`. On `[n]`: transition directly.

**CRITICAL — chain continuation (no stop):** After macos-ux returns, do NOT produce any text and do NOT wait. Set artifact, transition, proceed to Step H2.

**[Autopilot default: "No". Emit: "Gate H1c: autopilot — skip macOS UX ✓"]**

#### Step H2 — Plan (EnterPlanMode)

1. Emit: "Hybrid path — entering plan mode with SPEC context..."
2. Call `EnterPlanMode`.
3. Read SPEC.md (and BRAINSTORM.md if present) plus relevant project files.
4. Propose a 4–8 task plan derived from the spec. Each task: goal, files to change, test to run.
5. Wait for user approval in plan mode.
6. On approval: call `ExitPlanMode`, emit "Plan approved — executing...", transition `step_h2_plan → step_h3_execute`.

#### Step H3 — Execute

**Uncommitted-changes guard (before any Edit/Write on source files):**
```bash
git -C <project_root> status --short 2>/dev/null
```
If output is non-empty, present `AskUserQuestion` before touching any file:
- `Commit first (Recommended)` — stop here; commit existing changes, then re-invoke the chain.
- `Proceed anyway` — plan edits will mix with existing uncommitted changes; emit a warning line before starting.
- `Abort` — exit with no writes.

Execute the approved plan directly with Edit/Write/Bash tool calls. No sub-agents.
After completing each plan task, emit a one-line progress update before starting the next:
`"Task N/M — <brief description>: done."`

After all plan tasks are complete:
- Run the project test command if `test_cmd != NONE`.
- **REQUIRED — two separate manifest-transition calls, not one:**
  1. Transition `step_h3_execute → gate_h3_verify` (call manifest-transition.sh now).
  2. Present Gate H3 (AskUserQuestion below).
  3. Based on user response, transition `gate_h3_verify → step_h5_commit` or `gate_h3_verify → step_h4_review`.
  Collapsing these into a single `step_h3_execute → step_h5_commit` call is an illegal transition and will exit 1.

#### Gate H3 — Verify and review decision (AskUserQuestion)

```
question: "Gate H3 — Hybrid path: implementation complete\n\nFiles modified: <list>\nTest result: <PASS/FAIL/skipped>\n\nChoose next action:"
header: "Gate H3 · Verify"
options:
  - label: "Commit now"
    description: "Skip review, invoke commit skill."
  - label: "Run review cycle"
    description: "Invoke review-triage-fix skill, then commit."
  - label: "Abort"
    description: "Stop here."
```

`Commit now` → transition `gate_h3_verify → step_h5_commit`.
`Run review cycle` → transition `gate_h3_verify → step_h4_review`.
`Abort` → abort.

#### Step H4 — Review (conditional)

Invoke `review-triage-fix` skill (Skill tool). After it completes, transition `step_h4_review → step_h5_commit`.

#### Step H5 — Commit

Invoke `commit` skill (Skill tool). Transition `step_h5_commit → completed`.

---

## 5. HITL gates

**Immediate feedback rule (all gates):** after each HITL response (AskUserQuestion), immediately emit
**a brief text before any tool call** (manifest-transition.sh, Bash, Skill, Agent).
Recommended format: `"Gate N approved ✓ — <what happens next>..."`.
This prevents the prolonged silence that makes the user think the chain is blocked.

**Autopilot mode (`manifest.autopilot = true`):**
When `autopilot = true`, every gate listed below skips its `AskUserQuestion` and auto-selects the safe default. Emit one line before proceeding: `"Gate N: autopilot — <choice> ✓"`. The per-gate default is listed inline as **[Autopilot default: ...]** after each gate definition. Gates that are already conditional silent no-ops (e.g. Gate 0b/0c when remote is private) remain unchanged. The stop-gate hook, TOFU guard, and circuit breaker (deep-refactor) still apply — autopilot only bypasses the human-decision layer, not the safety layer.

---

**Gate 0 — Chain routing (ADR-0017, always fires)**

Trigger: `step_0_init`, always. Auto-detect recommendation computed before display (see §2 Form A step 7).

Display:

**Before rendering the gate, prepend any applicable warnings to the question string:**
- If `skill_exists=true` → prepend: `"⚠ A skill named '<topic-slug>' already exists in ~/.claude/skills/ — is this an upgrade rather than a new build?\n\n"`
- If `spec_topic_match=unknown` (SPEC.md present but no slug marker) → prepend: `"⚠ SPEC.md present but its topic could not be verified — confirm it belongs to this chain before choosing Standard/brownfield.\n\n"`
- `spec_topic_match=false` never reaches Gate 0 (gate0-detect.sh already flipped mode=greenfield, so the SPEC is disowned before routing).

```yaml
question: "Gate 0 — Chain routing (Human choice required)\n\nRecommended: [<path>] — <auto_detect_reason>\n\nChoose the orchestration path for: <topic-full-title>"
header: "Gate 0 · Chain"
options:
  - label: "[e] Express — native plan, single session, no docs"
    description: "Best for: <10 files, prototype, script. Zero sub-agents. Zero artifacts except manifest."
  - label: "[h] Hybrid — interview → SPEC.md, then plan mode in same session"
    description: "Best for: 5–20 files, 1–2 layers, clear requirements without ADR overhead."
  - label: "[s] Standard — full chain: interview → ADR → plan → fresh session → agents"
    description: "Best for: complex features, multi-layer, ADR required, or spec_adr_exist=true (brownfield)."
  - label: "[auto] Autopilot — Standard unattended (brownfield only)"
    description: "Standard path + all HITL gates auto-approved. REQUIRES SPEC.md to already exist — if absent the chain errors at Gate 1. Use for overnight runs on already-specced features."
```

After click:
- Write `chain_path` (top-level) in the manifest:
  ```bash
  sed -i.bak 's/^chain_path: null$/chain_path: "<path>"/' <manifest>
  ```
- Write `gate0.chain_path` and `gate0.auto_detect_reason` (nested, inline sed pattern):
  ```bash
  # Update gate0.chain_path and gate0.auto_detect_reason inside the gate0: block
  # Use python3 for reliable nested YAML editing (available on macOS):
  python3 -c "
  import re, sys
  txt = open('$manifest').read()
  txt = re.sub(r'(gate0:\n(?:  \w[^\n]*\n)*?  chain_path:) null', r'\1 \"$chain_path\"', txt)
  txt = re.sub(r'(gate0:\n(?:  \w[^\n]*\n)*?  auto_detect_reason:) null', r'\1 \"$reason\"', txt)
  open('$manifest', 'w').write(txt)
  "
  ```
- `[e]` → set `chain_path: express`. Proceed to step 8 (Gate 0b) in §2 Form A — the path begins after Gate 0d routes to `step_e1_plan` (§4 Express).
- `[h]` → set `chain_path: hybrid`. Proceed to step 8 (Gate 0b) in §2 Form A — the path begins after Gate 0d routes to `step_h1_interview` (§4 Hybrid).
- `[s]` → proceed to step 8 (Gate 0b) in §2 Form A. Standard path continues unchanged.
- `[auto]` → set `chain_path: standard` and `manifest.autopilot: true` via bash sed. **Pre-flight check:** verify `<project-root>/SPEC.md` exists. If absent: emit error `"Autopilot requires an existing SPEC.md (brownfield). Run /skill concept-to-code without autopilot to generate the SPEC first."` and abort chain. If present: emit `"Autopilot mode ON — all HITL gates will be auto-approved."` then proceed to step 8 (Gate 0b) in §2 Form A. Standard path continues with autopilot=true active.

---

**Gate 0b — Anonymous mode (conditional, fires only if detect-public-remote returns `public`)**

Trigger: `step_0_init`, after Gate 0, only if `~/.claude/skills/clean-public-repo/scripts/detect-public-remote.sh <project-root>` → `public`.
If the output is `silent`, Gate 0b is silent and shows nothing to the user.

Display (only if `public`):
```
============================================================
concept-to-code · Gate 0b · ANONYMOUS MODE
============================================================
Public remote detected: <repo from detect-public-remote>
Enable anonymous mode? Will produce output without tool markers
(minimal commits, no trace comments, no file slop, concise docs).
The decision is yours — never auto-applied.
============================================================
HITL Gate 0b: anonymize_decision
  [y] yes, enable anonymous mode (anonymize: true)
  [n] no, standard behavior (anonymize: false)
  [a] abort chain
> _
```

`[y]` → set `manifest.anonymize = true` (via `~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh <manifest> anonymize true`); proceed.
`[n]` → `manifest.anonymize = false` (default); proceed.
`[a]` → abort chain.

When `anonymize=false` (default), all dispatch templates remain **identical to today** → zero regressions.

---

> **Gate 0c (humanize) was removed** — see ADR-0040. Every artifact this chain produces (SPEC,
> ADR, plan, CLAUDE.md, code, commit) is internal, so the gate had nothing to act on. Gate 0b
> now leads straight to Gate 0d. The letter `0c` is not reused: gates are referenced by letter
> across this file and in `manifest-transition.sh` comments.

---

**Gate 0d — Scaffolding setup (conditional)**

Trigger: post Gate 0b, same `step_0_init`. Always fires (unconditional: every new chain needs scaffolding decisions recorded).

**[Autopilot default: skip AskUserQuestion entirely. Auto-set: `license: "None"`, `xcode_project: false`. For git: use auto-detect results (Outcome A/B/C) same as manual path. For commit: always `initial_commit_push: "commit"`, regardless of remote state (autopilot never pushes unattended; any separately-orchestrated automated publish flow runs after a local commit, never through this field — ADR-0020 D2). Emit: "Gate 0d: autopilot — scaffolding auto-configured ✓". Skip all secondary prompts (remote URL, anonymize re-confirm).]**

**Step 0 — Git auto-detect (runs before AskUserQuestion):**

Run the following bash to probe the project's existing git state:

```bash
_git_root="<project_root>"
_git_ok=$(git -C "$_git_root" rev-parse --is-inside-work-tree 2>/dev/null && echo "yes" || echo "no")
_git_remote=$(git -C "$_git_root" remote get-url origin 2>/dev/null || echo "")
```

Three outcomes:

**A — Git + remote already present** (`_git_ok=yes` AND `_git_remote` non-empty):
- Emit: `"Git auto-detected: <_git_remote> — skipping git setup questions."`
- Record to manifest via bash sed: `git_init: true`, `git_remote_url: "<_git_remote>"`
- Determine visibility: if `manifest.anonymize = true` → `git_visibility: "public"`, else → `git_visibility: "private"`
- Record `git_visibility` to manifest.
- Ask only **3 questions** (Q2, Q3, Q4 — Q1 and secondary remote URL prompt are skipped entirely).

**B — Git present, no remote** (`_git_ok=yes` AND `_git_remote` empty):
- Emit: `"Git repo detected but no remote configured."`
- Record to manifest: `git_init: true`
- Ask **3 questions** (Q1 reduced to visibility-only, Q3, Q4). Q1 becomes:
  ```
  question: "Git visibility?"
  header: "Git visibility"
  options:
    - label: "Private repo"
      description: "git_visibility=private"
    - label: "Public repo"
      description: "git_visibility=public; triggers anonymize check"
  ```
- Secondary remote URL prompt still fires if Q4 = push.

**C — No git** (`_git_ok=no`):
- Full 4-question survey as below.

---

**Full survey (Outcome C, or Q2-Q4 for Outcomes A/B):**

Use `AskUserQuestion`. For Outcome A use only the questions marked with their outcome letter. For Outcome C use all 4.

```
questions:
  - question: "Git repository?"        ← Outcome C only
    header: "Git repo"
    multiSelect: false
    options:
      - label: "Yes — private repo"
        description: "git_init=true, git_visibility=private"
      - label: "Yes — public repo"
        description: "git_init=true, git_visibility=public; triggers anonymize check"
      - label: "No git repo"
        description: "git_init=false; Steps 7 push + commit are skipped"

  - question: "License?"               ← all outcomes
    header: "License"
    multiSelect: false
    options:
      - label: "MIT"
        description: "Adds MIT LICENSE file at project root in Step 5"
      - label: "Apache-2.0"
        description: "Adds Apache-2.0 LICENSE file at project root in Step 5"
      - label: "GPL-3.0"
        description: "Adds GPL-3.0 LICENSE file at project root in Step 5"
      - label: "None"
        description: "No LICENSE file created"

  - question: "Xcode project?"         ← all outcomes
    header: "Xcode"
    multiSelect: false
    options:
      - label: "Yes"
        description: "Adds Xcode scaffold task to Step 2 architect brief and Step 5 coder dispatch"
      - label: "No"
        description: "Standard scaffold — no Xcode-specific tasks"

  - question: "Initial commit?"        ← all outcomes
    header: "Commit"
    multiSelect: false
    options:
      - label: "Commit and push to remote"
        description: "Step 7 commits then pushes; requires remote URL (prompted next if not auto-detected)"
      - label: "Commit only"
        description: "Step 7 commits; no push"
      - label: "No commit"
        description: "Chain ends after implementation; no Step 7 commit"
```

After user answers, record to manifest via bash sed substitution on the additive fields (NOT via Edit tool):

- Q1 "Yes — private repo" → `git_init: true`, `git_visibility: "private"`
- Q1 "Yes — public repo" → `git_init: true`, `git_visibility: "public"`
- Q1 "No git repo" → `git_init: false`, `git_visibility: "none"`
- Q2 license value → `license: "<MIT|Apache-2.0|GPL-3.0|None>"`
- Q3 "Yes" → `xcode_project: true`; "No" → `xcode_project: false`
- Q4 "Commit and push to remote" → `initial_commit_push: "push"`, then fire secondary remote URL question **only if `git_remote_url` is not already set (Outcomes B/C)**
- Q4 "Commit only" → `initial_commit_push: "commit"`
- Q4 "No commit" → `initial_commit_push: "none"`

**Secondary question — remote URL (conditional: push selected AND `git_remote_url` null):**

Skip entirely if `git_remote_url` was already populated by auto-detect (Outcome A).

If Q4 = "Commit and push to remote" AND `git_remote_url` is null:

```
question: "Gate 0d — Remote URL (Human input required)\n\nYou selected 'Commit and push to remote'.\nEnter the remote URL (e.g., git@github.com:user/repo.git or https://github.com/user/repo.git).\nChoose 'Skip' to set it manually later before Step 7."
header: "Gate 0d · Remote URL"
options:
  - label: "Skip — I will set it manually before Step 7"
    description: "git_remote_url stays null; push step will prompt again"
  - label: "Other (type URL in prompt)"
    description: "Paste the remote URL as a follow-up message; orchestrator records it in git_remote_url"
```

If user chooses "Other": wait for the follow-up message containing the URL, then record `git_remote_url: "<url>"` via bash sed substitution.
If user chooses "Skip": `git_remote_url` stays `null`.

**Secondary question — re-confirm anonymize (conditional on public repo):**

If Q1 = "Yes — public repo" AND `manifest.anonymize = false`:

```
question: "Gate 0d — Public repo detected. Anonymize deliverables? (Human approval required)\n\nYou chose a public repo. Enable anonymize mode?\nRewrites deliverables (README, docs, commits, PR) to remove AI tells, without altering facts or data."
header: "Gate 0d · Anonymize check"
options:
  - label: "Yes (recommended for public)"
    description: "manifest.anonymize = true; dispatch templates carry the anonymize directive"
  - label: "No — proceed without anonymization"
    description: "manifest.anonymize stays false"
```

`[yes]` → `~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh <manifest> anonymize true`; proceed.
`[no]` → proceed.

Transition: set `current_step` to `gate_0d_scaffolding` via `scripts/manifest-transition.sh`, then immediately transition based on `chain_path`:
- `chain_path = standard` (or null) → `gate_0d_scaffolding → step_1_interview`
- `chain_path = express` → `gate_0d_scaffolding → step_e1_plan`
- `chain_path = hybrid` → `gate_0d_scaffolding → step_h1_interview`

---

**Gate 1 — Spec review (blocking)**

Trigger: SPEC.md ready, `current_step = gate_1_spec_review`.

**Greenfield (interview just completed)** — use `AskUserQuestion`:
```
question: "Gate 1 — Spec review (Human approval required)\n\nArtifact: <absolute-path-to-SPEC.md>\nSummary: <5-line summary: objective, scope, stack, edge cases, success criteria>\nManifest: <manifest-path>\n\nOnly you can approve whether the spec captures the right requirements."
header: "Gate 1 · Spec"
options:
  - label: "Approve and proceed"
    description: "Proceed to Gate 1b (optional brainstorm)"
  - label: "Reject and revise"
    description: "Provide notes → re-invoke interview-driver"
  - label: "Abort chain"
    description: "Terminate the chain"
```

**Brownfield (pre-existing SPEC)** — use `AskUserQuestion`:
```
question: "Gate 1 — Pre-existing SPEC (Human approval required)\n\nArtifact: <project-root>/SPEC.md (pre-existing, not regenerated)\nMode: brownfield — interview skipped to avoid overwriting the SPEC.\nManifest: <manifest-path>\n\nOnly you can confirm whether this spec should be used as-is."
header: "Gate 1 · Spec"
options:
  - label: "Approve existing SPEC"
    description: "Proceed to Gate 1b"
  - label: "Regenerate via interview (→ greenfield)"
    description: "Set mode: greenfield, re-invoke interview-driver"
  - label: "Abort chain"
    description: "Terminate the chain"
```

Brownfield regenerate: set `mode: greenfield`, invoke `interview-driver`. Covers the case
"SPEC exists but I want to redo it".

Reject/greenfield behavior: transition back to `step_1_interview`; re-invoke `interview-driver` with notes as prefix.

**[Autopilot default: "Approve and proceed" (both greenfield and brownfield). Emit: "Gate 1: autopilot — spec auto-approved ✓"]**

---

**Gate 1b — Brainstorm (optional)**

Trigger: Gate 1 approved, `current_step` transitions to `gate_1b_brainstorm_decision`.

Use `AskUserQuestion`:
```
question: "Gate 1b — Brainstorm (optional)\n\nSPEC ready: <artifacts.spec>\nExplore design alternatives before locking the ADR?\nThe brainstorm produces BRAINSTORM.md that feeds the architect.\n\nThis is your choice — skipping proceeds directly to the architect."
header: "Gate 1b · Brainstorm"
options:
  - label: "Yes, explore with design-brainstorm"
    description: "Invoke design-brainstorm, then architect with brief"
  - label: "No, go directly to architect"
    description: "Standard behavior, zero regressions"
```

"No" → direct transition to `step_2_architecture`. `artifacts.brainstorm` stays null. Zero regressions.
"Yes" → invoke `design-brainstorm`, then populate `artifacts.brainstorm`, then `step_2_architecture`.

**[Autopilot default: "No, go directly to architect". Emit: "Gate 1b: autopilot — skip brainstorm ✓"]**

---

**Gate 1c — macOS UX design (optional, conditional)**

Trigger: after Gate 1b resolves (either branch) AND macOS detection grep returns `MACOS_DETECTED`.
If detection returns `NOT_MACOS`, this gate is silently skipped — zero behavior change for non-macOS projects.

Use `AskUserQuestion`:
```
question: "Gate 1c — macOS UX design (optional)\n\nmacOS/SwiftUI project detected.\nDesign the window structure, navigation, Settings, and menu bar layout before the architect?\nProduces UX-BLUEPRINT.md — a HIG-compliant skeleton the architect will follow.\n\nThis is your choice — skipping proceeds directly to the architect."
header: "Gate 1c · macOS UX"
options:
  - label: "Yes, design with macos-ux"
    description: "Interview-driven HIG blueprint: windows, navigation, Settings, menus, shortcuts"
  - label: "No, go directly to architect"
    description: "Standard behavior, zero regressions"
```

"No" → transition `gate_1c_macos_ux_decision → step_2_architecture`. `artifacts.ux_blueprint` stays null. Dispatch architect.

"Yes" → emit "Gate 1c: macOS UX design active ✓ — invoking macos-ux...". Invoke the `macos-ux` skill in-session:
```
Use the macos-ux skill.
Chain context: concept-to-code (gate 1c).
Project root: <project-root>.
Requirements source: SPEC.md at <project-root>/SPEC.md.
Design the macOS UX skeleton for this app: window types, navigation, Settings, menu bar,
toolbar, keyboard shortcuts, accessibility baseline.
Write the structured blueprint to <project-root>/UX-BLUEPRINT.md.
Do NOT write SPEC, ADR, or plan. Do NOT invoke writing-plans.
Do NOT produce a closing summary or handoff message after writing UX-BLUEPRINT.md.
Return silently — the concept-to-code orchestrator continues immediately after.
```
**CRITICAL — chain continuation (no stop):** After the macos-ux Skill tool returns,
do NOT produce any text response and do NOT wait for user input. Proceed IMMEDIATELY to:
1. Write `artifacts.ux_blueprint = <project-root>/UX-BLUEPRINT.md` in the manifest (bash script update).
2. Transition `gate_1c_macos_ux_decision → step_2_architecture`.
3. Dispatch architect with UX blueprint in context (see architect brief — `artifacts.ux_blueprint` is now non-null).

**[Autopilot default: "No". Emit: "Gate 1c: autopilot — skip macOS UX ✓"]**

---

**Gate 2 — Architecture review (blocking)**

Trigger: architect agent returns, `current_step = gate_2_architecture_review`.

**Gate 2a — Architecture (always present):**

Use `AskUserQuestion`:
```
question: "Gate 2 — Architecture review (Human approval required)\n\n
  ADR:  <absolute-path>\n
  Plan: <absolute-path>\n
  ARCH: <absolute-path or 'not generated'>\n
  Anonymize: <ON|OFF>\n\n
  Key decisions:\n  • <dec1>\n  • <dec2>\n  • <dec3>\n\n
  Risk flags:\n  • <risk1>\n  • <risk2>\n  • <risk3>\n\n
  Only you can approve this architecture before implementation begins."
header: "Gate 2 · Arch"
options:
  - label: "Approve"
    description: "Proceed to Gate 2b (test-cmd) if present, then Step 3"
  - label: "Reject and revise"
    description: "Provide feedback → re-dispatch architect"
  - label: "Abort"
    description: "Terminate the chain"
```

Reject behavior: transition back to `step_2_architecture`; re-dispatch architect with the feedback as addendum.

**[Autopilot default: "Approve". Emit: "Gate 2: autopilot — architecture auto-approved ✓"]**

**Gate 2b — Test-cmd TOFU (only if test-cmd candidate != NONE):**

After the user approves Gate 2a, immediately emit: **"Gate 2 approved ✓ — proceeding to Gate 2b / Step 3..."**.
If `manifest.test_cmd_candidate` is **absent or == `NONE`**: transition to `step_3_project_memory`. Proceed to Step 3 directly (no Gate 2b).
If `manifest.test_cmd_candidate` is present (not null) and ≠ `NONE`:

Use `AskUserQuestion`:
```
question: "Gate 2b — Project test-cmd (Human approval required)\n\nCommand proposed by architect:\n\n`<command>`\n\n
  Do you approve this command as the authoritative test runner?\n
  To modify it select 'Edit' or 'Other' and type the correct command.\n\n
  Only you can authorize this command to be SHA-pinned as trusted."
header: "Gate 2 · TOFU"
options:
  - label: "Approve"
    description: "The command is registered as authoritative (SHA-pinned)"
  - label: "Edit"
    description: "Select 'Other' to type the correct command; orchestrator writes it and asks for re-confirmation"
  - label: "Skip (use NONE)"
    description: "Leave the NONE placeholder, tests not automatically run in the chain"
  - label: "Abort"
    description: "Terminate the chain"
```

After "Approve" click: emit "Gate 2b approved ✓ — registering test-cmd and proceeding to Step 3...".
1. `bash ~/.claude/hooks/approve-test-cmd.sh <project-root>` — verify output contains "Approved for".
2. Transition to `step_3_project_memory`. Proceed to Step 3.

After "Edit" / "Other" with correct command provided by user:
1. Write the new line in `.claude/test-cmd`.
2. Re-show Gate 2b with the new command (same AskUserQuestion structure).
3. Only after the second "Approve" call `approve-test-cmd.sh`.

After "Skip": `manifest.test_cmd_placeholder = true`. Transition to `step_3_project_memory`. Proceed to Step 3.
After "Abort": terminate the chain.

**[Autopilot default: never call `approve-test-cmd.sh` unconditionally (ADR-0014, ADR-0020 D4 —
TOFU trust must pre-exist, never auto-granted in autopilot). Probe pre-existing trust read-only,
the exact same mechanism as the Form-B resume-path guard (`SKILL.md:152-158`, unmodified):
```bash
TCF="<project-root>/.claude/test-cmd"
H=$(shasum -a 256 "$TCF" | awk '{print $1}')
ROOT_N=$(cd "<project-root>" && pwd -P | tr '[:upper:]' '[:lower:]')
grep -qxF "${H}	${ROOT_N}" "$HOME/.claude/state/stop-gate/trust" 2>/dev/null \
  && echo "TRUSTED" || echo "NOT_TRUSTED"
```
- `TRUSTED` → the SHA-pinned `(hash, normalized-root)` pair already exists from a prior
  interactive approval; **reading** existing trust is not **granting** it. Proceed silently to
  `step_3_project_memory`. Emit: "Gate 2b: autopilot — pre-existing trust found, proceeding ✓".
- `NOT_TRUSTED → autopilot must never establish trust unattended` — do exactly what the
  interactive "Skip" branch above does: `manifest.test_cmd_placeholder = true`; transition to
  `step_3_project_memory`. Emit: "Gate 2b: autopilot — test-cmd not yet trusted, deferring to a
  human session (test_cmd_placeholder=true) ✓". Never call `approve-test-cmd.sh` on this branch.]**

---

**Gate 3 — Project memory review (blocking)**

Trigger: Step 3 produces `CLAUDE.md.proposed` (Branch A: orchestrator direct append; Branch B: `claude-md-generator`), `current_step = gate_3_project_memory_review`.

Before showing the gate: run the diff/show content in text output, then use `AskUserQuestion`:
- If `CLAUDE.md` does NOT exist: show full content (max 100 lines) as text, then gate.
- If `CLAUDE.md` exists: run `diff CLAUDE.md CLAUDE.md.proposed`, show only added lines as text, then gate.

**Line-count guard (Feature 5, Branch A only):** count lines in `CLAUDE.md.proposed`:
```bash
_lines=$(wc -l < "<project-root>/CLAUDE.md.proposed")
```
If `$_lines > 180`, prepend to the question string:
`"⚠ CLAUDE.md.proposed is $_lines lines (blueprint target <200). Consider running /skill claude-md-slim on this file after implementation to extract path-scoped rules.\n\n"`

```
question: "Gate 3 — Project memory review (Human approval required)\n\nProposed: <project-root>/CLAUDE.md.proposed\n(diff / content shown above)\nManifest: <manifest-path>\n\nOnly you can decide whether this project memory is correct before it is applied."
header: "Gate 3 · Memory"
options:
  - label: "Approve (create/overwrite CLAUDE.md)"
    description: "mv CLAUDE.md.proposed → CLAUDE.md with backup .bak-<date>"
  - label: "Reject and revise"
    description: "Provide notes → re-invoke claude-md-generator (Branch B) or ask orchestrator to revise the appended section (Branch A)"
  - label: "Skip (no CLAUDE.md change)"
    description: "project_claude_md = null, proceed to Gate 4"
  - label: "Abort chain"
    description: "Terminate the chain"
```

**STOP — after showing this AskUserQuestion and receiving the response, your turn ends only if the user approves/skips/aborts. If they reject: re-invoke claude-md-generator.**

Skip behavior: `manifest.artifacts.project_claude_md = null`, transition to `step_4_session_boundary`.
Reject behavior: re-invoke `claude-md-generator` with feedback prefix.

**[Autopilot default: "Approve (create/overwrite CLAUDE.md)". Execute `mv CLAUDE.md.proposed CLAUDE.md` automatically. Emit: "Gate 3: autopilot — CLAUDE.md auto-applied ✓". Transition to `step_4_session_boundary`.]**

---

**Gate 4 — Session boundary (BLOCKING)**

Trigger: post Gate 3, manifest in `step_4_session_boundary`.

**[Autopilot bypass: if `manifest.autopilot = true`, skip AskUserQuestion entirely. Emit: "Gate 4: autopilot — session boundary bypassed, continuing to Step 5 ✓". Transition `step_4_session_boundary → ready_for_implementation`. Immediately proceed to Step 5 — do NOT stop, do NOT emit the /clear instructions block.]**

Use `AskUserQuestion` (only when `manifest.autopilot = false`):
```
question: "Gate 4 — Implementation (Human action required)\n\n
  Steps 1–3 complete, manifest at ready_for_implementation. Choose how to run Steps 5-7.\n\n
  Autopilot now: implement in this session, local commit, no push or PR.\n
  Fresh session: stop here, /clear or open a new session, then resume for the cleanest coder context.\n\n
  Only you can choose."
header: "Gate 4 · Implement"
options:
  - label: "Implement now (autopilot, this session)"
    description: "Runs Steps 5-7 unattended: implement, local commit via commit --autopilot, no push, no PR. Review the diff and push after. Same-session context, mitigated since coders dispatch as isolated subagents."
  - label: "Confirmed — I will /clear and resume"
    description: "The chain stops here. Resume with /skill concept-to-code resume in the new session for the cleanest coder context."
  - label: "Abort chain"
    description: "Terminate the chain. The manifest stays on disk; you can resume later."
```

**After the user clicks "Implement now (autopilot, this session)":**
1. Set the flag: `bash ~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh <manifest-path> autopilot true`.
2. Emit: "Gate 4: implement now — autopilot ON for Steps 5-7 ✓".
3. Transition `step_4_session_boundary → ready_for_implementation`.
4. Proceed directly to Step 5 in this session. Do NOT emit the `/clear` block. Do NOT stop. From here
   `manifest.autopilot = true` drives every downstream gate (5, 5.05, 5.06, 5.1, 5.5) to its safe
   default, and Step 7 commits with `--autopilot` (local only, no push/PR). The stop-gate hook, TOFU
   guard, and circuit breaker still apply.

**After the user clicks "Confirmed":**
1. Transition `step_4_session_boundary → ready_for_implementation`.
2. Immediately emit this block as your final text output (no other tool calls):

```
Gate 4 confirmed ✓ — chain paused at ready_for_implementation.

Run these two commands now:

  /clear

  /skill concept-to-code resume <manifest-path>
```

**STOP — after emitting the above text, your turn ends here.**
**Do not dispatch coder. Do not continue with Step 5. Do not run any other tools.**
The manifest is now at `ready_for_implementation`. The fresh session will detect this state and restart from Step 5.

Note: `/clear` cannot be triggered automatically from within the skill — it is a UI-only command. The two-line block above is the closest possible automation.

**After the user clicks "Abort chain":**
Emit: "Gate 4: chain aborted. Manifest left at `step_4_session_boundary` — run `/skill concept-to-code resume <manifest-path>` to continue later."
STOP — no further tool calls.

---

**Gate 5 — Review cycle decision (optional)**

Trigger: post Step 5 (coder complete), `current_step = gate_5_review_decision`.

Use `AskUserQuestion`:
```
question: "Gate 5 — Review cycle (Human approval required)\n\nTasks completed: <N>\nFiles modified: <list>\nTests: <green | red | n/a>\nHarness delta: <if relevant>\nAnonymize: <ON if manifest.anonymize=true | OFF (default)>\n\nRun a review-triage-fix cycle? Estimated: 5-10 min.\n\nOnly you can decide whether a review cycle is needed."
header: "Gate 5 · Review"
options:
  - label: "Run review-triage-fix"
    description: "Full cycle: review → triage → fix → re-review (~5-10 min)"
  - label: "Skip review"
    description: "Proceed directly to commit"
  - label: "Abort chain"
    description: "Terminate the chain"
```

"Skip review": emit "Gate 5: skip review ✓ — proceeding to Gate 5.05...". Then evaluate Gate 5.05.
"Run review-triage-fix": emit "Gate 5: review cycle ✓ — dispatching review-triage-fix...". Dispatch `review-triage-fix`. **Immediately after review-triage-fix returns (do NOT wait for user input), evaluate Gate 5.05.**

**[Autopilot default: "Skip review". Emit: "Gate 5: autopilot — review skipped ✓"]**

---

**Gate 5.05 — UI layout audit (conditional, auto-run)**

Trigger: after Gate 5 (review complete or skipped), before Gate 5.1.

Check whether any UI files were modified in this cycle:
```bash
git diff --name-only HEAD | grep -E '\.(swift|html|css|tsx|jsx|vue)$'
```

- **Output is empty:** emit "Gate 5.05: no UI files changed — skipping layout audit ✓". Proceed to Gate 5.1.
- **Output non-empty:** emit "Gate 5.05: UI files detected — running ui-layout-audit...". Invoke `Skill(skill="ui-layout-audit")`. **Immediately after ui-layout-audit returns (do NOT wait for user input), proceed to Gate 5.1.**

No AskUserQuestion — the skill auto-applies P1/P2 fixes and reports P3 as recommendations.

**[Autopilot default: same conditional logic — auto-run if UI files present. Emit: "Gate 5.05: autopilot — ui-layout-audit <ran|skipped> ✓"]**

---

**Gate 5.06 — Specialized type + error review (conditional, user-gated)**

Trigger: after Gate 5.05, before Gate 5.1.

Evaluate condition: does the modified file set (manifest.artifacts.plan completion section or the list shown at Gate 5) include at least one `.ts`, `.tsx`, `.js`, `.jsx`, `.swift`, or `.py` file?

- **No matching files:** emit "Gate 5.06: no typed files — skipping specialized review ✓". Proceed to Gate 5.1.
- **Matching files found:** present `AskUserQuestion`:

```
question: "Gate 5.06 — Specialized type + error review\n\nRun silent-failure-hunter (error handling audit) and type-design-analyzer on the modified files?\nReport-only — no auto-fixes. Estimated: 3–5 min.\n\nOnly you can decide whether this extra review dimension is needed."
header: "Gate 5.06 · review"
options:
  - label: "Run (errors + types)"
    description: "Dispatch two specialized reviewer agents in parallel. Report-only."
  - label: "Skip (proceed to Gate 5.1)"
    description: "Silent no-op — chain continues unchanged."
  - label: "Abort chain"
    description: "Terminate the chain."
```

"Run (errors + types)": emit "Gate 5.06: specialized review active ✓ — dispatching reviewer agents...". Dispatch **in parallel** using the Agent tool:
```
Agent({ agentType: "reviewer",
        prompt: "SCOPE: silent-failure-hunter — error handling audit.\nReview the following files for: empty or swallowed catch blocks, ignored return values or Result types, optional chaining masking failures, unhandled Promise rejections, broad exception catches that hide root causes, and error objects logged without actionable context.\nReport only — do not edit any file. Output findings grouped by severity: CRITICAL / IMPORTANT / SUGGESTIONS.\nFiles: <modified-file-list-from-manifest>" })

Agent({ agentType: "reviewer",
        prompt: "SCOPE: type-design-analyzer — structural type quality audit.\nReview the following files for: stringly-typed IDs or enums (String where a newtype/wrapper should be used), missing discriminated unions (raw string/int where a sealed type fits), anemic models (pure DTOs with no invariants or behavior), nullable fields that should never be null, weak encapsulation exposing internal state, and protocol/interface misuse.\nReport only — do not edit any file. Output findings grouped by severity: CRITICAL / IMPORTANT / SUGGESTIONS.\nFiles: <modified-file-list-from-manifest>" })
```
Wait for both agents. Merge the two finding lists, deduplicate by file+location, then present the aggregated result as a single severity table (CRITICAL / IMPORTANT / SUGGESTIONS). Emit "Gate 5.06: specialized review complete ✓". **Proceed immediately to Gate 5.1 — no additional HITL.**

"Skip (proceed to Gate 5.1)": emit "Gate 5.06: skipped ✓ — proceeding to Gate 5.1...". Proceed to Gate 5.1.

"Abort chain": emit "Gate 5.06: aborted ✓ — terminating chain.". Then abort.

**[Autopilot default: "Skip". Emit: "Gate 5.06: autopilot — specialized review skipped ✓"]**

---

**Gate 5.1 — Deep refactor (conditional)**

Trigger: post Gate 5 (review complete or skipped), pre Gate 5.6. Always shown.

Use `AskUserQuestion`:
```
question: "Gate 5.1 — Run deep-refactor? (Human approval required)\n\nOptional whole-codebase health audit across four dimensions (dead-code, perf, structure, security).\nAuto-fixes low/medium-risk findings dimension-by-dimension under a global circuit breaker.\nEstimated: 10-20 min depending on codebase size.\n\nOnly you can decide whether a deep-refactor cycle is needed."
header: "Gate 5.1 · Refactor"
options:
  - label: "Run deep-refactor"
    description: "Invoke /skill deep-refactor on the project root, then proceed to Gate 5.6"
  - label: "Skip (proceed to Gate 5.6)"
    description: "Silent no-op — Gate 5 → Gate 5.6 behavior is unchanged"
  - label: "Abort chain"
    description: "Terminate the chain"
```

"Run deep-refactor": emit "Gate 5.1: deep-refactor active ✓ — invoking deep-refactor skill...". Invoke Skill(skill="deep-refactor", args="<project_root>"). Regardless of how deep-refactor exits (completed / aborted by user / errored), proceed to Gate 5.6.
"Skip (proceed to Gate 5.6)": emit "Gate 5.1: skipped ✓ — proceeding to Gate 5.6...". Proceed to Gate 5.6 (zero behavior change).
"Abort chain": emit "Gate 5.1: aborted ✓ — terminating chain.". Then abort.

**[Autopilot default: "Skip". Emit: "Gate 5.1: autopilot — deep-refactor skipped ✓"]**

---

**Gate 5.6 — Transition to commit (unconditional, no user prompt)**

Trigger: post Gate 5.1, pre Step 7.

Transition `<current_step> → step_7_commit` (current_step is `step_6_review` if RTF ran, or
`gate_5_review_decision` if review was skipped — both are valid source states), then proceed
directly to Step 7 (`commit` skill).

> This step is what remains of **Gate 5.5 (humanize deliverables), removed per ADR-0040**. The
> gate listed README, CHANGELOG, ADR prose, `.md` docs and SPEC.md as its targets, and every one
> of those is an internal artifact that no longer takes a humanize pass. Its state transition was
> load-bearing, so it stays here; the humanize action and its `AskUserQuestion` are gone. The
> letter `5.5` is not reused.

---

## 6. Coexistence invariants

This skill DOES NOT modify any of the following. They remain active and orthogonal:

- `~/.claude/agents/coder.md` — Pre-flight Pattern Classifier (ADR-0001) fires in Step 5 by default.
- `~/.claude/agents/reviewer.md` — Pattern-drift check (ADR-0001) fires implicitly in Step 6 review cycle.
- `~/.claude/agents/refactorer.md` — Snapshot Harness Integration (ADR-0002) is orthogonal (refactorer not dispatched by this skill).
- `~/.claude/agents/architect.md` — carries the ADR-0012 contract (factor in `PRIOR AGENT NOTES`, emit terminal `DURABLE NOTES:`). This skill's Step 2 template now injects prior notes and harvests durable notes via `agent-notes-harvest.sh` (orchestrator-side, path encoded resolved by the orchestrator only); it still does not edit architect.md at runtime.
- `~/.claude/skills/review-triage-fix/SKILL.md` — v1.2 Add+Remove rule invoked as-is in Step 6; it also carries the ADR-0012 inject/harvest contract for `reviewer`/`debugger` internally (those agents are dispatched by it, not by this skill).
- `~/.claude/skills/interview-driver/SKILL.md` — invoked as-is in Step 1 (greenfield only).
- `~/.claude/skills/claude-md-generator/SKILL.md` — invoked as-is in Step 3 (additive directive conveyed in the prompt template, not in claude-md-generator's SKILL.md).
- `~/.claude/skills/design-brainstorm/SKILL.md` — invoked at gate 1b (`[y]`). Writes only `BRAINSTORM.md`; this skill updates `artifacts.brainstorm` in the manifest.
- `~/.claude/skills/macos-ux/SKILL.md` — invoked at gate 1c / gate H1c (`[y]`), conditional on macOS/SwiftUI SPEC detection. Writes only `UX-BLUEPRINT.md`; this skill updates `artifacts.ux_blueprint` in the manifest. Design mode only in chain; review mode is standalone.
- `~/.claude/hooks/` — `approve-test-cmd.sh`, `stop-gate.sh` unchanged. (ADR-0014: Step 2 now WRITES a *candidate* `.claude/test-cmd` proposed by the architect and requests approval at Gate 2; the TOFU/SHA-pinned trust mechanism and stop-gate enforcement remain identical — the chain proposes, it does not touch the trust.)
- `~/.claude/settings.json`, `.mcp.json`, `.claude/rules/` — unchanged.

- `~/.claude/skills/commit/SKILL.md` — invoked in Step 7 as the chain's final step. Manages HITL gate, Conventional Commits message generation, and PR option autonomously. The orchestrator calls it via the `Skill` tool with `context-hint = "<topic-full-title> (ADR: <adr-path>)"`. Commit is made only after an explicit user click.
- `~/.claude/skills/deep-refactor/SKILL.md` — invoked at Gate 5.1 (conditional, AskUserQuestion gate); modifies target project source files and writes a report; does not update chain manifest, hook, or RTF state.

- `~/.claude/skills/clean-public-repo/SKILL.md` — **recommended skill** (ADR-0011): for retroactive cleanup of existing repos, invokable on request after the chain. NOT invoked automatically.
  The chain's **anonymous mode** (`anonymize: true`) is distinct: it activates via Gate 0b and acts
  on the dispatch templates (Step 2 + Step 5) without modifying `coder.md`/`architect.md`.
  When `anonymize=false` (default), the templates remain identical to today → zero regressions.

Sub-agent constraint (blueprint §2): this skill instructs the **orchestrator** (main CLI agent).
Sub-agents dispatched by the orchestrator (`architect`, `coder`) do NOT spawn further sub-agents.
Nesting is supported since CC 2.1.172 but kept flat by design — see blueprint §2.2 for the rationale.

---

## 7. Failure handling

**Policy: abort, no auto-retry.**

On any tool error, API failure, or unexpected exit during a Step:

1. Write any partial artifact with `.partial` extension (e.g., `ADR-0003.md.partial`).
2. Update manifest: `status = failed`, `failure.failed_at = <now>`, `failure.failed_step = <step>`, `failure.failure_reason = <reason-string>`.
3. Stop. Do NOT proceed to the next step.

**Reason strings (examples):**
- `"architect_dispatch_failed:api_overload_529"`
- `"interview_aborted_or_incomplete"`
- `"claude_md_generation_failed"`
- `"architect_timeout_60s"`

**Manual recovery by user:**
- Read the manifest to identify `failure.failed_step` and `failure.failure_reason`.
- Fix the underlying issue (e.g., wait for API rate limit, correct permissions).
- Re-invoke the skill with the same topic (restarts from the failed step).
- Or mark the chain aborted: `/skill concept-to-code abort <manifest-path>`.

**No force-retry, no skip-to-next.** Each step depends on the previous one's output.
If `status = completed`, the chain is done — create a new manifest for a new topic.

**Long-running command guardrail (blocked pattern):**

The harness blocks `sleep N && <any-command>` chains. This pattern appears when the orchestrator
starts a slow Bash command (rsync, build, deploy) and tries to poll its output file afterward.

Correct approach for any long-running Bash command:
- Use `run_in_background: true` on the Bash call — the harness notifies you automatically on completion.
- Do NOT follow it with `sleep N && tail <file>`. Do NOT chain a sleep to work around the block.
- If you need to check task output, use the `TaskOutput` tool — never `tail` on the output file path.

```
# WRONG — blocked:
sleep 30 && tail -30 /private/tmp/.../tasks/<id>.output

# CORRECT — wait for the background notification after:
Bash({ command: "rsync ...", run_in_background: true })
# harness re-invokes when done; read output via TaskOutput(<task-id>)
```

This applies to any slow operation inside the chain: rsync over SMB, `npm run build`, `xcodebuild`,
`pytest` with a large suite. Always background + notify, never sleep-poll.

**Dev-server port guard (pre-start, mandatory):**

Before starting any long-running dev server (`reflex run`, `npm run dev`, `vite`, `next dev`,
`python -m http.server`, etc.), verify the expected ports are free:

```bash
lsof -ti :<frontend-port> -ti :<backend-port>
```

- Output non-empty → a previous instance (or orphan) holds the ports. STOP: terminate the
  existing background task (`TaskStop`) or kill the orphan explicitly, then start fresh.
- NEVER accept a silent fallback to alternate ports (e.g. Reflex rebinding 3000→3001,
  8000→8001). Two instances sharing one project dir corrupt each other (`EEXIST` link
  errors in `.web/node_modules`, backend worker crash loops) and health checks become
  ambiguous — a `200` may come from the stale instance.
- If the server log shows "Address already in use ... will run on port <N+1>", treat it as
  a failure: stop the task, clear the ports, restart. Do not proceed to tests.
