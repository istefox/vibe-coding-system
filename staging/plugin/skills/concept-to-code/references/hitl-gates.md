
**Immediate feedback rule (all gates):** after each HITL response (AskUserQuestion), immediately emit
**a brief text before any tool call** (manifest-transition.sh, Bash, Skill, Agent). <!-- path-rule-exempt: enumerates kinds of tool call (transition, Bash, Skill, Agent), not a command to run -->
Recommended format: `"Gate N approved ✓ — <what happens next>..."`.
This prevents the prolonged silence that makes the user think the chain is blocked.

**Autopilot mode (`manifest.autopilot = true`):**
When `autopilot = true`, every gate listed below skips its `AskUserQuestion` and auto-selects the safe default. Emit one line before proceeding: `"Gate N: autopilot — <choice> ✓"`. The per-gate default is listed inline after each gate definition, in one of **two** marker forms — both colon-terminated so they can be checked mechanically:

- **[Autopilot default: ...]** — the gate still runs and one of its options is auto-selected. This is the form thirteen of the gates use.
- **[Autopilot bypass: ...]** — the gate is skipped outright rather than answered. **Gate 4 only.** Do not normalise it to `default:`: the semantics differ, and `recovery-preflight.test.sh` (`RH4`, `RI1`) uses `**[Autopilot bypass` as an awk extraction boundary, so changing the spelling breaks two assertions in another file.

A gate that legitimately needs neither — a container heading whose sub-gates carry their own, or a step that raises no `AskUserQuestion` at all — declares that in one line: `<!-- autopilot-gate-exempt: <reason> -->`, reason ≥ 40 characters, on the marker line itself. **The stop-gate hook, TOFU guard, and circuit breaker (deep-refactor) still apply — autopilot only bypasses the human-decision layer, not the safety layer.**

**This paragraph was a promise nothing kept until issue #329 (ADR-0115).** Gate 0 — the chain's *first* gate, which fires on every feature — carried no marker at all, so an unattended run raised a question `/goal` cannot answer (ADR-0022) and stalled before doing any work. Nothing in the harness asserted the contract; section G of `concept-to-code-bsd-autopilot-gates.test.sh` now derives every gate in this section at run time and requires a marker or a declared exemption. The old sentence exempting "conditional silent no-ops (e.g. Gate 0b/0c when remote is private)" is gone: it was true only in the *private* case, and Gate 0b prompts when the remote is public.

---

**Gate 0 — Chain routing (ADR-0017, always fires)**

Trigger: `step_0_init`, always. Auto-detect recommendation computed before display (see §2 Form A step 7).

Display:

**Before rendering the gate, prepend any applicable warnings to the question string:**
- If `skill_exists=true` → prepend: `"⚠ A skill named '<topic-slug>' already exists in ~/.claude/skills/ — is this an upgrade rather than a new build?\n\n"`
- If `spec_topic_match=unknown` (SPEC.md present but no slug marker) → prepend: `"⚠ SPEC.md present but its topic could not be verified — confirm it belongs to this chain before choosing Standard/brownfield.\n\n"`
- `spec_topic_match=false` never reaches Gate 0 (gate0-detect.sh already flipped mode=greenfield, so the SPEC is disowned before routing). **"Disowned" settles routing and nothing else — the file itself is handled by Step 1's archive fence (ADR-0096), not here.** Until issue #228 that sentence was the whole of the system's response to a mismatched SPEC, and the file was overwritten in place.

**Two recommendations used to appear in this box and neither was declared to win (issue #227,
ADR-0098).** The auto-detect line said one thing; the global `AskUserQuestion` convention has the
orchestrator put its own choice first with `(Recommended)`, and the two can legitimately differ —
the vote is mechanical, the orchestrator may hold context the vote cannot see.

**The orchestrator's recommendation wins.** The auto-detect is advisory and is labelled as such.
**When they disagree, say so in the question** — name both, and give the reason for overriding, in
one line prepended to the question string:

```text
Auto-detect suggests [<auto-path>] — <auto_detect_reason>. Recommending [<chosen-path>] instead: <why>.
```

A silently resolved disagreement is the defect; showing the user two signals and which one you
followed is the fix. When they agree, prepend nothing.

**What `repo_file_count` measures: repository size, not feature size.** It counts files in the
repository, which at Gate 0 is the only size signal that exists — there is no SPEC and no plan yet.
`file_vote` turns `standard` at 20 files, so on any real repository it is a constant, and feeding
that into the majority rule leaves exactly two reachable auto-recommendations: `standard` when the
title carries an architecture keyword, `hybrid` otherwise. **So `express` can never be
auto-recommended on a repository of 20 files or more** — it stays available as a click, never as a
suggestion. Corroborated by the corpus: three manifests ever recorded a `file_vote`, all three
`standard`. Weigh the vote accordingly when your own judgement differs.

```yaml
question: "Gate 0 — Chain routing (Human choice required)\n\nAuto-detect suggests: [<path>] — <auto_detect_reason>\n\nChoose the orchestration path for: <topic-full-title>"
header: "Gate 0 · Chain"
options:
  - label: "[e] Express — native plan, single session, no docs"
    description: "Best for: <10 files, prototype, script. Zero sub-agents. Zero artifacts except manifest."
  - label: "[h] Hybrid — interview → SPEC.md, then plan mode in same session"
    description: "Best for: 5–20 files, 1–2 layers, clear requirements without ADR overhead."
  - label: "[s] Standard — full chain: interview → ADR → plan → fresh session → agents"
    description: "Best for: complex features, multi-layer, ADR required, or spec_adr_exist=true (brownfield)."
  - label: "[auto] Autopilot — Standard unattended (brownfield only)"
    description: "Standard path + all HITL gates auto-approved. REQUIRES SPEC.md to already exist — if absent the routing pre-flight at §2 step 7b aborts the chain. Use for overnight runs on already-specced features."
```

**[Autopilot default: `[s]` standard. Set `chain_path: standard`, emit `"Gate 0: autopilot — standard ✓"`, and proceed. This is `[auto]` minus the one thing `[auto]` adds, because by the time this gate is reached unattended `autopilot` is already `true` — `project-conductor` sets it before invoking the chain. **It is NOT the auto-detect vote**, and that is the load-bearing part: `hybrid` reaches Step H1, which invokes `interview-driver` *unconditionally* (unlike standard Step 1, it has no brownfield skip), and `express` reaches plan mode. Only `standard` can complete with nobody present. The SPEC.md pre-flight that used to sit inside the `[auto]` branch now runs at **§2 Form A step 7b** for every route, including the `express|hybrid|standard` prefix fast path that skips this gate entirely — do not reinstate a copy here.]**

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
- `[auto]` → set `chain_path: standard` and `manifest.autopilot: true` via bash sed, emit `"Autopilot mode ON — all HITL gates will be auto-approved."`, then proceed to step 8 (Gate 0b) in §2 Form A. Standard path continues with autopilot=true active. **The SPEC.md pre-flight is not here.** It used to be, and inside this branch it was unreachable by the only caller that needs it: on the autopilot path `autopilot` is already `true` before Gate 0 renders, so nobody ever clicks `[auto]` and the check never ran (issue #329). It now runs at **§2 Form A step 7b**, once, for every route. Two copies of one safety question is the worst available shape — they can disagree about whether the gate fires.

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

**[Autopilot default: `[n]` — `anonymize` stays `false`, the same value the `silent` branch leaves, and the same value a private remote produces. Emit `"Gate 0b: autopilot — anonymize off ✓"` and proceed. Never `[y]`: enabling anonymisation is the user's decision and is never auto-applied, which the line below states unconditionally. This marker exists because the old contract exempted Gate 0b as a "conditional silent no-op" — true only when the remote is **private**. On a public remote this gate prompts, and unattended it would stall exactly as Gate 0 did (issue #329).]**

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
# issue #407: `rev-parse --is-inside-work-tree` prints "true" on its OWN stdout on success, and
# that capture the command substitution — without a stdout redirect on the probed command itself
# — sees "true\nyes", never the bare "yes" every branch below compares against. Redirect the
# probe's own stdout to /dev/null so only the echo's output is captured.
_git_ok=$(git -C "$_git_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 && echo "yes" || echo "no")
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

**Gate 0d transition block:**

Transition: set `current_step` to `gate_0d_scaffolding` via `~/.claude/skills/concept-to-code/scripts/manifest-transition.sh`, then immediately transition based on `chain_path`:
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

**Record the gate outcome** — see *Gate approval recording* in §5: `~/.claude/skills/concept-to-code/scripts/manifest-set-gate.sh <manifest-path> 1 approved "<spec accepted>"`, or `rejected` with the reason, before the transition.

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
  - label: "No, skip macOS UX"
    description: "Standard behavior, zero regressions. Gate 1d (Claude Design) is offered next either way."
```

"No" → transition `gate_1c_macos_ux_decision → gate_1d_claude_design_decision`. `artifacts.ux_blueprint` stays null. Present Gate 1d (see below).

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
2. Transition `gate_1c_macos_ux_decision → gate_1d_claude_design_decision`.
3. Present Gate 1d (see below) — architect dispatch happens after Gate 1d resolves, not here.

**[Autopilot default: "No". Emit: "Gate 1c: autopilot — skip macOS UX ✓"]**

---

**Gate 1d — Claude Design (optional)**

Trigger: Gate 1b or Gate 1c resolves (either branch of either gate — Gate 1d always fires, last
of the three, so the generated prompt can quote `BRAINSTORM.md`'s adopted approach and
`UX-BLUEPRINT.md`'s HIG skeleton when they exist). `current_step = gate_1d_claude_design_decision`.

**No detector. This gate is unconditional and always offered, and it always defaults to "No"
(VCS-052, ADR-0181).** Gate 1c's macOS detector fired on meta-SPECs in this repo and never on a
real macOS app (ADR-0093) — here the dangerous direction is inverted: a false negative would hide
the very gate the user asked for. An always-offered gate that defaults to "No" costs one click and
makes no claim about the SPEC, so there is nothing about it to be wrong.

**1d-A — generate the prompt.** Use `AskUserQuestion`:
```
question: "Gate 1d — Claude Design (optional)\n\nSPEC ready: <artifacts.spec>\nGenerate a Claude Design (claude.ai/design) prompt to produce an initial visual mockup before the architect?\nThis requires a human in a browser on a Pro/Max/Team/Enterprise plan — there is no API.\n\nThis is your choice — skipping proceeds directly to the architect."
header: "Gate 1d · Claude Design"
options:
  - label: "Yes, generate a Claude Design prompt"
    description: "Invoke claude-design-brief, write DESIGN-PROMPT.md, then bring back a shared URL"
  - label: "No, go directly to architect"
    description: "Standard behavior, zero regressions"
  - label: "Abort"
    description: "Terminate the chain"
```

"No" → transition `gate_1d_claude_design_decision → step_2_architecture`. `artifacts.design_prompt`
and `artifacts.design` stay null. Dispatch architect.

"Abort" → terminate the chain.

"Yes" → emit "Gate 1d: generating Claude Design prompt ✓ — invoking claude-design-brief...".
Invoke the `claude-design-brief` skill in-session:
```
Use the claude-design-brief skill.
Chain context: concept-to-code (gate 1d).
Project root: <project-root>.
Requirements source: SPEC.md at <project-root>/SPEC.md.
If present, also read BRAINSTORM.md at <manifest.artifacts.brainstorm> for the adopted approach,
and UX-BLUEPRINT.md at <manifest.artifacts.ux_blueprint> for platform constraints (quote verbatim).
Compose a single copy-paste-ready Claude Design prompt and write it to
<project-root>/DESIGN-PROMPT.md.
Do NOT write SPEC, ADR, plan, or DESIGN.md. Do NOT invoke writing-plans.
Do NOT produce a closing summary or handoff message after writing DESIGN-PROMPT.md.
Return silently — the concept-to-code orchestrator continues immediately after.
```
**CRITICAL — chain continuation (no stop):** After the claude-design-brief Skill tool returns,
do NOT produce a closing/handoff sentence on the skill's behalf. Proceed IMMEDIATELY to:
1. Write `artifacts.design_prompt = <project-root>/DESIGN-PROMPT.md` in the manifest (bash script update).
2. Emit: "Gate 1d: prompt written ✓ — <project-root>/DESIGN-PROMPT.md. Go to claude.ai/design
   (Pro/Max/Team/Enterprise plan required), paste the fenced block, ask for N screens, and share
   with link access." **Do not transition** — the chain stays at `gate_1d_claude_design_decision`.
3. Present **1d-B** (below) in the same turn.

**1d-B — bring back the result.** Use `AskUserQuestion`:
```
question: "Gate 1d-B — Bring back the Claude Design result\n\nPaste the shared URL you got from claude.ai/design.\nThree tiers change downstream fidelity:\n  • URL only — provenance plus whatever you type under Binding decisions.\n  • URL + standalone-HTML export (recommended) — a file the coder can actually read.\n  • URL + handoff bundle — an opaque directory, recorded as-is (composition unverified).\nStill designing? Choose 'Not yet' — this pauses here, resumable across a break of days."
header: "Gate 1d-B · Design result"
options:
  - label: "Paste the shared URL"
    description: "Other → the URL. Optionally append ' + export:<path>' for a local HTML export, or ' + bundle:<path>' for a handoff bundle — omit either and the tier is URL only."
  - label: "Not yet, still designing"
    description: "Pause here; resume later, same manifest, same gate — the Gate 2c pause shape."
  - label: "Skip after all"
    description: "No Claude Design artifact — proceed straight to the architect."
```

"Not yet, still designing" → do **not** transition. `current_step` stays
`gate_1d_claude_design_decision`, resumable the same way any other mid-chain pause is (Form-B
resume path) — this must survive a pause of days, exactly like Gate 2c's "Not yet — I will
provision now".

"Skip after all" → transition `gate_1d_claude_design_decision → step_2_architecture`.
`artifacts.design` stays null (`artifacts.design_prompt` keeps whatever 1d-A already set, or
stays null if 1d-A was never reached). Dispatch architect.

"Paste the shared URL" → parse the `Other` answer for the URL (first `https://` token) and any
` + export:<path>` / ` + bundle:<path>` suffix. **CRITICAL — chain continuation (no stop):** once
the URL is parsed, do NOT produce a text response and do NOT wait for user input. Proceed
IMMEDIATELY to:
1. Run `bash ~/.claude/skills/concept-to-code/scripts/design-url-check.sh --url <url>`.
   - exit 0 → `URL shape check: valid`.
   - exit 1 → the shape did not match `^https://claude\.ai/`. Re-present **1d-B** with a note
     that the URL didn't look right — do NOT write DESIGN.md, do NOT transition.
   - exit 3 (DID-NOT-RUN, rule 4) → `URL shape check: did-not-run`. Proceed anyway — a checker
     that could not run is not evidence the URL is wrong, and the human who pasted it already
     validated it by hand; never silently write "valid" for this case.
2. Write `<project-root>/DESIGN.md`:
   ```markdown
   # Design — <topic>
   Source: Claude Design (claude.ai/design)
   Shared URL: <url>
   URL shape check: valid | invalid | did-not-run
   Captured: <ISO-8601 timestamp>
   Prompt: DESIGN-PROMPT.md
   Local export: <export path> | none
   Handoff bundle: <bundle path> | none   <!-- composition UNVERIFIED -->

   ## Screens
   | Screen | Purpose | SPEC ids | Notes |

   ## Binding decisions
   ## Not decided here
   ```
   The `## Screens` table, `## Binding decisions`, and `## Not decided here` sections are filled
   in from whatever the human transcribes when pasting the URL (or left as headers with no rows,
   which `design-coverage.sh` at Gate 2 will flag as DID-NOT-RUN — the denominator guard, rule 7).
3. Run `bash ~/.claude/skills/concept-to-code/scripts/manifest-set-artifact.sh <manifest-path> design <project-root>/DESIGN.md`.
4. Transition `gate_1d_claude_design_decision → step_2_architecture`.
5. Dispatch architect with the design artifact in context (see architect brief —
   `artifacts.design` is now non-null).

**Autopilot: always "No", and it is structural, not a preference (VCS-052, ADR-0181).** The
artifact requires a human in a browser on a paid plan; no unattended branch can produce one. Same
family as Gate 2b's TOFU and Gate 2c's provisioning pause — an unattended agent must not be the
one deciding a design is "done".

**[Autopilot default: "No". Emit: "Gate 1d: autopilot — Claude Design needs a human in a browser, skipped ✓"]**

---

**Gate 2 — Architecture review (blocking)**

<!-- autopilot-gate-exempt: a container heading only — sub-gates 2a, 2b and 2c are what actually prompt, and each carries its own autopilot default -->

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

**Record the gate outcome** — see *Gate approval recording* in §5: `~/.claude/skills/concept-to-code/scripts/manifest-set-gate.sh <manifest-path> 2 approved "<architecture accepted>"`, or `rejected` with the reason, before the transition.

**[Autopilot default: "Approve". Emit: "Gate 2: autopilot — architecture auto-approved ✓"]**

**Protected-interface proposal (ADR-0053 §D6, only if the architect's report includes a
`PROPOSED PROTECTED INTERFACES:` block):** show that block's entries and reasons alongside Gate
2a's key decisions. Approving Gate 2a approves the architecture, **not** the protection — it does
NOT create `.claude/protected-interfaces`. State this explicitly so it is not assumed: the
operator creates the file by hand if they want the protection. `interface-check.sh` BLOCKS once
the file exists (ADR-0053 §D2), so a declaration the operator did not knowingly make is a block
they will not understand. No new manifest gate, no new transition — this rides on Gate 2a's
existing HITL review.

**Audit-profile proposal (ADR-0055 §D5, only if the architect's report includes a
`PROPOSED AUDIT PROFILE:` block):** show that block's `risk`/`task_type` values and one-line
reasons alongside Gate 2a's key decisions. Approving Gate 2a confirms the proposed profile too —
unlike the protected-interface proposal above, this one IS written by the orchestrator on
approval, because `risk`/`task_type` are manifest fields the orchestrator already owns (the
architect's write scope excludes the manifest entirely — see `agent-write-scope.sh`). On
"Approve", after the CLAUDE.md/Gate-2a bookkeeping above:
```bash
sed -i.bak 's/^risk: null$/risk: "<PROPOSED_RISK>"/' "<manifest>"
sed -i.bak 's/^task_type: null$/task_type: "<PROPOSED_TASK_TYPE>"/' "<manifest>"
```
On "Reject and revise": the profile proposal is revised together with the rest of the
architecture, on the same re-dispatch path as Gate 2a — do not write `risk`/`task_type` before
the re-approval. If the architect's report has no `PROPOSED AUDIT PROFILE:` block, `risk` and
`task_type` stay `null`, which resolves to the strict profile (ADR-0055 §D2), never to "no profile
applies". The operator confirms; nothing here is auto-derived and applied silently (§D5) — see
`#### Proportional audit depth` above for the resolution rule this sets up.

**[Autopilot default: same as Gate 2a — accept the proposed profile if present (run the two `sed`
substitutions above), else leave `risk`/`task_type` null (strict). This inherits the existing
"architecture auto-approved" default rather than adding a new leniency branch — ADR-0055's own
negative consequence names self-assessed risk as weak evidence, and §D4's floor is the actual
mitigation, not a stricter autopilot branch here.]**

**Gate 2b — Test-cmd TOFU (only if test-cmd candidate != NONE):**

After the user approves Gate 2a, immediately emit: **"Gate 2 approved ✓ — proceeding to Gate 2b / Step 3..."**.
If `manifest.test_cmd_candidate` is **absent or == `NONE`**: transition to `step_3_project_memory`. Proceed to Step 3 directly (no Gate 2b).
If `manifest.test_cmd_candidate` is present (not null) and ≠ `NONE`:

**Probe pre-existing trust FIRST, read-only, before showing anything (issue #233, ADR-0102).** One
probe, above the branch split, read by the attended and autopilot paths alike — this is the single
resolution site inside Gate 2b, and the autopilot block at the end of this gate consumes its result
rather than repeating it. A second copy of a trust probe is a probe that can disagree with itself
about whether a safety gate fires.

<!-- fence-contract: c2c-gate2b-trust-probe -->
```bash
# ADR-0133 §D1 (issue #394): the body between the two FENCE_BASH lines runs under BASH, not under
# the host shell. No `export` prologue — this body binds everything it reads, from the substituted
# `<project-root>` placeholder. Terminator at COLUMN 0; an indented one is swallowed into the
# here-document and destroys this fence's exit code silently. `$HOME` is exported by every shell, so
# it crosses the boundary unaided.
bash <<'FENCE_BASH'
TCF="<project-root>/.claude/test-cmd"
H=$(shasum -a 256 "$TCF" | cut -d' ' -f1)
ROOT_N=$(cd "<project-root>" && pwd -P | tr '[:upper:]' '[:lower:]')
grep -qxF "${H}	${ROOT_N}" "$HOME/.claude/state/stop-gate/trust" 2>/dev/null \
  && echo "TRUSTED" || echo "NOT_TRUSTED"
FENCE_BASH
```

- **`TRUSTED` → do NOT show the gate.** Emit one line — `"Gate 2b: test-cmd already trusted, SHA
  unchanged — gate skipped ✓"` — and transition to `step_3_project_memory`. **Reading existing trust
  is not granting it**, which is why this is a skip and not a bypass; the same sentence the autopilot
  branch below has always carried.

  The reason to skip rather than ask is not the click. A gate that fires with a foregone answer,
  every run, on every brownfield project, is a gate people learn to approve without reading — and
  this is the gate that guards arbitrary command execution. A safety gate that cries wolf is worse
  than one that fires rarely.

- **`NOT_TRUSTED` → present the gate below, unchanged.**

**Two invariants this skip does not touch, stated here rather than only in §4's TOFU rules, because
this is where a reader deciding to skip is standing.** **NEVER call `approve-test-cmd.sh` before the
user's explicit click** — the probe reads trust and never creates it. And the pin is on **content**:
if the SHA differs from the trusted one the gate fires even when the command *looks* identical,
because **a changed file is a new authorisation**.

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
TOFU trust must pre-exist, never auto-granted in autopilot). **Consume the probe already run at the
top of this gate** — it is the same read-only mechanism as the Form-B resume-path guard
(**Step 2b — TOFU guard (resume path only)**, unmodified), and since issue #233 it runs once for
both paths rather than being repeated here:
- `TRUSTED` → the SHA-pinned `(hash, normalized-root)` pair already exists from a prior
  interactive approval; **reading** existing trust is not **granting** it. Proceed silently to
  `step_3_project_memory`. Emit: "Gate 2b: autopilot — pre-existing trust found, proceeding ✓".
- `NOT_TRUSTED → autopilot must never establish trust unattended` — do exactly what the
  interactive "Skip" branch above does: `manifest.test_cmd_placeholder = true`; transition to
  `step_3_project_memory`. Emit: "Gate 2b: autopilot — test-cmd not yet trusted, deferring to a
  human session (test_cmd_placeholder=true) ✓". Never call `approve-test-cmd.sh` on this branch.]**

---

**Gate 2c — External dependencies (only if the architect's report contains at least one
`EXTERNAL DEPENDENCY:` line — G13, ADR-0060):**

**Resolution** (`plugin/scripts/`, deployed to `hooks/` — same shape as `secret-scan.sh` /
`dependency-scan.sh`, not the `skills/concept-to-code/scripts/` shape `spec-coverage.sh` uses,
because this gate is shared with `autopilot/SKILL.md` too):
```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/scripts/external-dependency-check.sh" ]; then
  _edep="$CLAUDE_PLUGIN_ROOT/scripts/external-dependency-check.sh"
elif [ -f "$HOME/.claude/hooks/external-dependency-check.sh" ]; then
  _edep="$HOME/.claude/hooks/external-dependency-check.sh"
else
  _edep=""     # neither resolves — gate did not run, do not infer a clean result
fi
```

`external-dependency-check.sh` is a CHECKER, exactly like `spec-coverage.sh` (ADR-0048): the exit
code is the policy channel, never `weakening-scan.sh`'s always-0 reporter idiom.
```bash
if [ -n "$_edep" ]; then
  _eout=$(printf '%s\n' "<architect's report text>" | bash "$_edep" 2>"$_edep_err"); _erc=$?
fi
```
`_erc = 0` → every declared dependency is verified `provisioned: true` (or is a kind this gate
cannot probe, in which case the declaration is trusted — see below), or none were declared (no
Gate 2c line at all — this whole gate is skipped, §D5). `_erc = 1` → at least one is not
provisioned, or is declared `provisioned: true` but a verifiable kind's probe finds it absent;
`_eout` carries `UNMET<TAB><name><TAB><kind><TAB><state>` lines, and the stderr captured in
`$_edep_err` names the human action required for each. `_erc = 2`, or `$_edep` empty: the gate did
not run — proceed to the `AskUserQuestion` below anyway, noting automatic verification was
unavailable, rather than silently treating it as clean.

**On `_erc = 0`, check `_eout` for `UNVERIFIED<TAB><name><TAB><kind><TAB>declared-true` lines before
deciding what happens next (issue #473, ADR-0164).** These are dependencies of a kind the gate
cannot probe (an OAuth/consent flow, a vendor account) — trusted, not verified, and that
distinction has to reach the human:
- `_eout` empty → every declared dependency was actually VERIFIED (or none were declared): write
  `external_dependencies` into the manifest from the declared lines and proceed directly to Gate 3
  — nothing for a human to decide, the gate itself confirmed the state.
- `_eout` non-empty (one or more `UNVERIFIED` lines) → these dependencies were never checked
  against the world, only trusted on the architect's word. Present them via `AskUserQuestion`,
  reusing the same question shape as the `_erc = 1` case below but naming them as UNVERIFIED
  rather than UNMET, before writing `external_dependencies` and proceeding to Gate 3.

Otherwise, present via `AskUserQuestion`:
```
question: "Gate 2c — External dependencies (Human confirmation required)\n\n
  This feature declares:\n  • <name> (<kind>) — provisioned: <declared state>\n  ...\n\n
  An unattended agent cannot complete a consent flow or create a credential mid-task (ADR-0060
  §D2). Confirm each dependency is already provisioned before implementation begins."
header: "Gate 2 · Deps"
options:
  - label: "Confirmed — all provisioned now"
    description: "Write external_dependencies with provisioned: true and proceed to Gate 3"
  - label: "Not yet — I will provision now"
    description: "Pause the chain here; resume after provisioning"
  - label: "Abort"
    description: "Terminate the chain"
```
On "Confirmed": write `external_dependencies` into the manifest (bash sed, one entry per declared
dependency, `provisioned: true`). Transition to `step_3_project_memory`.
On "Not yet": do not transition; the chain stays at Gate 2c, resumable the same way any other
mid-chain pause is (Form-B resume path).
On "Abort": terminate the chain.

**[Autopilot default: never self-confirm (ADR-0060 §D2 — the same no-self-approval rule as Gate
2b's TOFU trust and ADR-0023's gh-auth wall: an unattended agent cannot verify its own consent
flow, so it must not be the one deciding "provisioned: true"). On `_erc = 1`:
- If `<project-root>/.claude/autopilot-state/active` exists (running under `autopilot`):
  write a per-feature skip note to `<project-root>/.claude/autopilot-state/skipped-features`
  (append, NOT `.claude/needs-human` — ADR-0060 §D3), mark the feature `[~]` in PROJECT.md with
  the same reason, and return `skipped` to the conductor so the roadmap continues to the next
  feature. This is the "autopilot Phase P" call site referenced by ADR-0060 §D4: it fires here, at
  this feature's own Gate 2c inside the per-feature chain `autopilot` §3.3 drives, not
  literally inside that skill's Phase P step (dependencies are not declared until the architect
  runs) — documented in `autopilot/SKILL.md` because it reuses that phase's per-feature
  skip mechanism (§3.3, "Marker contract").
- Otherwise (plain `autopilot-build`, no autopilot roadmap to continue): hard-abort this chain,
  reporting the `UNMET` lines and the human action required. There is nothing else to skip to.
On `_erc = 0`, or `$_edep` empty: proceed exactly like the interactive "Confirmed" path (writing
`external_dependencies` when `_erc = 0`; leaving it unset when the gate could not run), no
AskUserQuestion shown, no self-approval of anything the gate could not itself verify.]**

---

**Gate 3 — Project memory review (blocking)**

Trigger: Step 3 produces `CLAUDE.md.proposed` (Branch A: orchestrator direct append; Branch B: `claude-md-generator`), `current_step = gate_3_project_memory_review`.

Before showing the gate: run the diff/show content in text output, then use `AskUserQuestion`:
- If `CLAUDE.md` does NOT exist: show full content (max 100 lines) as text, then gate.
- If `CLAUDE.md` exists: run `diff CLAUDE.md CLAUDE.md.proposed`, show only added lines as text, then gate.

**Ceiling guard (Branch A only):** defined once at Step 3 Branch A step 4, not restated here.
Compute `wc -l < "<project-root>/CLAUDE.md.proposed"` and prepend the warning string given there
when the count exceeds the ceiling. Two copies of one threshold is two answers to one question
waiting to disagree (ADR-0086's criterion) — and they already had, which is how issue #380 found
this one: the Step 3 copy had been corrected and this one still carried the retired 180-line form
and its dead `claude-md-slim` remedy.

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

**Record the gate outcome** — see *Gate approval recording* in §5: `~/.claude/skills/concept-to-code/scripts/manifest-set-gate.sh <manifest-path> 3 approved "<applied|skipped>"`, or `rejected` with the reason, before the transition.

**[Autopilot default: "Approve (create/overwrite CLAUDE.md)". Execute `mv CLAUDE.md.proposed CLAUDE.md` automatically. Emit: "Gate 3: autopilot — CLAUDE.md auto-applied ✓". Transition to `step_4_session_boundary`.]**

---

**Gate 4 — Session boundary (BLOCKING)**

Trigger: post Gate 3, manifest in `step_4_session_boundary`.

#### Gate approval recording (issue #238, ADR-0099)

**Named once here; every gate branch below references it.** `manifest-set-gate.sh` shipped correct,
tested and deployed with **no instructed call site anywhere in the chain**, so every approval a
human gave was recorded nowhere and the trail stayed `pending` for the life of the manifest.
Measured before the fix: 39 of 164 gate entries across 41 manifests were `approved`, and the
distribution is bimodal — four manifests at 4/4, thirteen at 1/4. That is not gates being answered
differently, it is orchestrators remembering differently.

**Record the gate outcome** immediately after each gate's click, before the transition:

```bash
bash ~/.claude/skills/concept-to-code/scripts/manifest-set-gate.sh <manifest-path> <N> <status> "<notes>"
```

`<status>` is `approved` or `rejected`. `<notes>` is short and factual — which option was chosen,
or why it was rejected. Exit 3 means the gate has no slot in this manifest, which for gates 1–5 on a
Standard chain means the manifest predates ADR-0099; report it and proceed rather than halting, since
a missing audit line is not a reason to stop a chain a human is standing in front of.

**Gate 4's notes are load-bearing in a way the others' are not.** `autopilot: true` alone **cannot
distinguish a human choosing unattended implementation from a roadmap pre-authorising the whole
run** — `project-conductor`'s autopilot mode sets the identical flag with no human at Gate 4 at all
(ADR-0022). The chosen option name in `notes` is the only thing that tells them apart afterwards.

No status invariant is added to `manifest-validate.sh`, deliberately. A chain legitimately sits at
`pending` mid-run, and a completed chain with a pending Gate 5 is a real state — the
`step_6_review → completed` direct close skips it. Any status check would have to be conditional on
`current_step`, which is ADR-0076's rule and the same trap.

#### Gate 4.0 — Commit the planning artifacts (ADR-0071)

**Run on every path that proceeds past Gate 4, and on none that does not.** Named once here; the
three proceeding branches below each reference it, and "Abort chain" does not — an aborted chain
must not leave a commit behind.

Step 5's recovery pre-flight (5.0.1, 5.0.2) requires a clean working tree on a feature branch.
Until ADR-0071 **nothing in the chain produced that state**: Steps 1–3 always write `SPEC.md`, the
ADR, the plan and the manifest, and the chain always starts wherever the user was — so every first
run failed the pre-flight, and the remediation it printed (`git stash push -u`) would have stashed
the coder's own inputs. This step is the producer.

Invoke the `commit` skill — never hand-rolled `git` here. Its Step 3.6 creates the feature branch <!-- commit-order-exempt: Gate 4.0 commits an in-flight manifest by design (ADR-0071 producer role); this rule concerns manifest writes inside a commit-invoking step, not a ban on ever committing a non-terminal manifest. -->
and structurally refuses to commit to the default branch, its Step 4 is the HITL gate, and Step 7
of this chain already uses it, so there is exactly one commit path in the system:

- **Attended** (`manifest.autopilot = false`): invoke `commit` with args
  `<topic-full-title> — planning artifacts (ADR: <manifest.artifacts.adr>) --no-pr
  --branch feat/<manifest.topic> --include
  <spec>[,<manifest.artifacts.brainstorm>][,<manifest.artifacts.ux_blueprint>][,<manifest.artifacts.design_prompt>][,<manifest.artifacts.design>],<manifest.artifacts.adr>,<manifest.artifacts.plan>,<manifest-path>`.
  Each bracketed entry (VCS-052, ADR-0181) is included only when that manifest field is non-null;
  a null entry is DROPPED from the comma list entirely — never emitted as an empty slot between two
  commas. This is an **INSTRUCTION** (rule 16), not a mechanically enforced parse: a chain that ran
  none of Gate 1b/1c/1d gets the original four-entry list, unchanged, zero regressions.
  The Step 4 gate still asks; `--no-pr` suppresses only the PR question, which would otherwise fire
  on every chain run with nothing to publish.
- **Unattended** (`manifest.autopilot = true`): the same, plus `--autopilot`. Local commit only —
  this changes no autonomy boundary, ADR-0020 already places a local commit inside it.

**`--branch feat/<manifest.topic>` is what makes the branch name agree with the publish step
(issue #363, ADR-0127 §D3), and the agreement is BY CONSTRUCTION rather than by an orchestrator
remembering.** Without it, `commit` Step 3.6 derives the name from the commit *subject*: this is a
planning-artifacts commit, so its type is `docs`, so the derived name is `chore/<subject-slug>` —
while `publish-feature.sh`'s `BRANCH="feat/$SLUG"` line pushes a name built from the topic slug.
**They never
coincide.** The 2026-08-04 run reached `AUTOPILOT-PUBLISH` only because a human created
`feat/<slug>` by hand beforehand, which is also what Step 5.0.2's own remediation message
prescribes — a hint the contract was assumed and never written down.

`<manifest.topic>` is the same field `publish-feature.sh` receives as `--slug`, so there is one
source for the name rather than two that agree today. Do not substitute the subject slug here:
that is the derivation this argument exists to bypass.

**`--include` is what makes this step able to produce anything at all (issue #234).** On a
greenfield chain those four artifacts are **untracked**, and `commit`'s default rule never stages
untracked *under any circumstance*; the one door — Step 4's "Stage additional files" — is exactly
what `--autopilot` skips. The fix looked at first like raw staging here, and it is not: `RH4b`
forbids every raw git command in this block, staging included, and staging from the caller would
put the file-scope decision in two places (ADR-0071 §D2 and its `## Clarification`). `CLAUDE.md` is deliberately absent from the list: it is tracked-modified, so the default scope already covers it, and naming a path that needs no naming invites the list to drift into a second scope rule.

If the tree is already clean AND `HEAD` is already off the default branch, `commit` reports nothing
to commit: that is a resumed or already-committed run, and it is a pass, not an error. Proceed.

If the commit is declined or aborted at its own gate, **do not transition** — Gate 4 stays
un-answered and the chain remains at `step_4_session_boundary`. Report that Step 5 will refuse to
dispatch until the artifacts are committed, and stop.

**[Autopilot bypass: if `manifest.autopilot = true`, skip AskUserQuestion entirely. Run **Gate 4.0**
first (with `--autopilot --no-pr`). Emit: "Gate 4: autopilot — session boundary bypassed, continuing
to Step 5 ✓". Transition `step_4_session_boundary → ready_for_implementation`. Immediately proceed to
Step 5 — do NOT stop, do NOT emit the /clear instructions block.]**

**Two independent choices, four cells, and until issue #237 this gate offered two of them (ADR-0097).**
WHERE Steps 5-7 run — this session or a fresh one — and HOW they run — attended, with Gates 5,
5.05, 5.06, 5.1 and 5.6 rendering and asking, or unattended with `autopilot = true` driving each to
its safe default. They are orthogonal, and collapsing them onto the diagonal meant staying
in-session was choosing to forfeit every downstream gate, with nothing saying so.

**What a fresh session actually buys is a clean ORCHESTRATOR context**, not a cleaner coder one. A
dispatched coder is an isolated subagent running in its own worktree (ADR-0068), so it never
carried this session's conversation either way. The orchestrator's headroom is real and affects the
briefs it writes — it is simply not the thing the old text named.

Use `AskUserQuestion` (only when `manifest.autopilot = false`):
```
question: "Gate 4 — Implementation (Human action required)\n\n
  Steps 1–3 complete, manifest at ready_for_implementation.\n\n
  Two independent choices: WHERE Steps 5-7 run (this session or a fresh one) and HOW (attended,
  every downstream gate asks — or unattended, each takes its safe default).\n\n
  Only you can choose."
header: "Gate 4 · Implement"
options:
  - label: "Implement now (attended, this session) (Recommended)"
    description: "Runs Steps 5-7 here with Gates 5, 5.05, 5.06, 5.1 and 5.6 active. Gives up nothing: the design context stays, every gate still asks. Costs you those clicks. Coders dispatch as isolated subagents in their own worktrees, so staying here does not pollute them."
  - label: "Implement now (autopilot, this session)"
    description: "Same place, unattended: every downstream gate takes its safe default and nobody reviews the review. Local commit via commit --autopilot, no push, no PR. Choose when you will not be watching."
  - label: "Confirmed — I will /clear and resume"
    description: "The chain stops here. Resume with /skill concept-to-code resume in a new session, which buys a clean orchestrator context — more headroom, briefs written without this session behind them. It does not change coder isolation. Attended by default; set autopilot in the manifest first if you want it unattended."
  - label: "Abort chain"
    description: "Terminate the chain. The manifest stays on disk; you can resume later."
```

The recommendation is the attended in-session option because it is the only one that forfeits
nothing — it keeps the design context and keeps every gate. The other three each trade something
away, which is a fine trade to make deliberately and a poor one to make by default.

**After the user clicks "Implement now (attended, this session)":**
0. Run **Gate 4.0** — attended form.
1. **Do NOT set `autopilot`.** It stays `false`, which is the entire difference between this branch
   and the one below, and it is one line away from being the same branch. Every downstream gate (5,
   5.05, 5.06, 5.1, 5.6) renders and asks.
2. Emit: "Gate 4: implement now — attended, this session ✓".
3. Transition `step_4_session_boundary → ready_for_implementation`.
4. Proceed directly to Step 5 in this session. Do NOT emit the `/clear` block. Do NOT stop.

**After the user clicks "Implement now (autopilot, this session)":**
0. Run **Gate 4.0** — attended form (the flag below is not set yet, and the human is present).
1. Set the flag: `bash ~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh <manifest-path> autopilot true`.
2. Emit: "Gate 4: implement now — autopilot ON for Steps 5-7 ✓".
3. Transition `step_4_session_boundary → ready_for_implementation`.
4. Proceed directly to Step 5 in this session. Do NOT emit the `/clear` block. Do NOT stop. From here
   `manifest.autopilot = true` drives every downstream gate (5, 5.05, 5.06, 5.1, 5.5) to its safe
   default, and Step 7 commits with `--autopilot` (local only, no push/PR). The stop-gate hook, TOFU
   guard, and circuit breaker still apply.

**After the user clicks "Confirmed":**
0. Run **Gate 4.0**. This is the path the producer exists for: the fresh session opens at Step 5 and
   asserts a clean tree on a feature branch, and it has no way to create either.
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

**Record the gate outcome for all four branches** — see *Gate approval recording* in §5: `~/.claude/skills/concept-to-code/scripts/manifest-set-gate.sh <manifest-path> 4 approved "<the option label the user clicked>"`, and `rejected "aborted at Gate 4"` on the abort branch. **The option name is the load-bearing part**: `autopilot: true` alone cannot distinguish a human choosing unattended implementation from a roadmap pre-authorising the whole run, and this note is the only thing that tells them apart afterwards.

**After the user clicks "Abort chain":**
Emit: "Gate 4: chain aborted. Manifest left at `step_4_session_boundary` — run `/skill concept-to-code resume <manifest-path>` to continue later."
STOP — no further tool calls.

---

**Gate 4.5 — Tracer-bullet red decision (conditional, fires only on `tracer_bullet_verdict = red`)**

Trigger: Step 4.5 (§4) computed `red`. Skipped entirely — no `AskUserQuestion`, no text shown — when
`tracer_bullet_mode = skip` (default) or the computed verdict is `green`/`amber`: those two route
automatically (§4 Step 4.5), never asked.

`red` is the outcome this feature exists for (ADR-0057 §D2), and the one an agentic chain is
structurally least likely to reach on its own: the chain is mid-run, the plan is approved, and every
incentive points at "continue". So this gate names **hand-code as a first-class option**, not a
buried sub-choice, and records the reason — without that, `red` degrades into a slower `amber`.

Use `AskUserQuestion`:
```
question: "Gate 4.5 — Tracer-bullet probe: red (Human decision required)\n\nThe thinnest end-to-end
  slice did not mechanically pass (build/run failed, or its test failed after 2 attempts).\n\n
  Coder's own recommendation (recorded, not authoritative): <tracer_bullet_recommendation>\n\n
  This is the outcome the probe exists to surface. Only you can decide how to proceed."
header: "Gate 4.5 · Red"
options:
  - label: "Continue anyway"
    description: "Proceed to Step 5 despite the failed probe. Recorded as a deliberate human override."
  - label: "Reduce scope"
    description: "Return to Gate 2 to revise the plan/ADR toward a smaller or different approach."
  - label: "Hand-code (abort)"
    description: "This class of work is not a good fit for unattended implementation right now. Abort the chain; the reason is recorded in the manifest."
```

"Continue anyway": set `tracer_bullet_red_decision: continue` (bash sed on the additive field).
Transition `ready_for_implementation → step_5_implementation` (the existing pair). Emit "Gate 4.5:
continuing despite red ✓".

"Reduce scope": set `tracer_bullet_red_decision: reduce_scope`. Transition
`ready_for_implementation → gate_2_architecture_review`. Emit "Gate 4.5: reducing scope — back to
Gate 2 ✓".

"Hand-code (abort)": set `tracer_bullet_red_decision: hand_code`. Record the reason in
`tracer_bullet_abort_reason` (bash sed, quote-escaped) — the user's stated reason if they gave one,
else the coder's own report summarized in one line. Transition to `aborted` (3-arg form:
`bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh <manifest> aborted aborted`).
Emit "Gate 4.5: hand-code — chain aborted, reason recorded ✓". **STOP — no further tool calls.**

**[Autopilot default: "Hand-code (abort)" — and deliberately NOT "Continue anyway", because
autopilot must never silently override a red probe. Set
`tracer_bullet_abort_reason: "autopilot: red tracer-bullet probe, no human present to decide — halting rather than guessing"`.
Emit: "Gate 4.5: autopilot — red probe, no unattended override, chain aborted ✓".]**

> The marker above was `**[Autopilot default is deliberately NOT …` until issue #329 — a third
> spelling that the §5 contract does not describe and no mechanical check could recognise. The
> argument is unchanged word for word; only the form is now the colon-terminated one, so section G
> of `concept-to-code-bsd-autopilot-gates.test.sh` can see it. Nothing extracted on the old
> spelling (verified by search before changing it), unlike Gate 4's `bypass:` form.

---

**Gate 5 — Review cycle decision (optional)**

Trigger: post Step 5 (coder complete), `current_step = step_6_review`.

**Gate 5 runs inline, as an inline sub-gate with no dedicated current_step state, the fifth of its
kind** — after Gate 2b (TOFU), Gate 4.5 (tracer-bullet red), and Gates 5.05/5.06. It had a state
declared for it, `gate_5_review_decision`, that nothing ever entered: Step 5 transitions to
`step_6_review` and presents this gate from there. Issue #265 (ADR-0105) removed the state rather
than adding a producer, because four siblings already work this way and the state was the anomaly.
**Do not reintroduce one** — the review decision is a branch inside `step_6_review`, not a phase of
its own.

**Advisory roll-up (ADR-0052 §D5 — read this before touching the block below).** `step5-report.json`
carries **this specific roll-up's six** advisory-schema arrays: `weakening_findings`,
`requirement_coverage` (its `uncovered` and `unscoped` lists — `unscoped` is a second list inside
this same member, added by ADR-0138, not a seventh array of its own), `checkpoint_reviews`, `tests_written_by`,
`suspect_findings` and `budget_findings` — a seventh, `accessibility_i18n_findings`, exists in the
same schema but is not one of these six; see below for why. Three of the six arrived in three
consecutive features, each individually justified by "blocking would be too noisy, so we surface
instead" — and their sum is not individually justified the same way (ADR-0052 §D5). **A report
nobody must act on is a report nobody reads** (ADR-0047 §D7), and the way that failure actually
arrives here is not one unreadable array, it is six readable ones stacked into a Gate 5 summary
that gets skimmed. So this block's volume tracks signal, not schema size:

- **If all six arrays are empty or absent:** render exactly ONE line — `Advisory findings: none
  across all six categories (weakening, requirement coverage, checkpoint reviews, tests-written-by,
  suspect findings, budget).` Do not additionally render six lines each saying "none" — that is the
  exact failure this roll-up exists to stop.
- **If at least one array is non-empty:** render ONLY the non-empty ones, each on its own line —
  never pad the summary with "X: none" lines for the arrays that have nothing. `suspect_findings`
  renders as before: a count and a per-detector breakdown, e.g. `Suspect findings: 3
  (zero-assertion-test: 2, swallowed-error: 1)`.
- **`budget_findings` specifically is capped at the top 5 entries by margin (descending), with a
  remainder count** — e.g. `Budget findings: 3 shown of 8, by margin descending (5 more not
  shown).` A per-task enumeration of a 40-task plan is not a summary; the full list still lives in
  `step5-report.json` for anyone who wants it.
- `weakening_findings` and `requirement_coverage.uncovered` are structurally near-always empty by
  the time Gate 5 renders — both are failure signals that block the Step 5 → `step_6_review`
  transition before this point (ADR-0047, ADR-0048). They are still evaluated for the
  all-six-empty roll-up line above, for the rare case a user pushed through an acknowledged failure
  signal manually.
- **`requirement_coverage.unscoped` does NOT inherit that "near-always empty" claim, by decision,
  not by adjacency (ADR-0138 §D3/§D5).** It rides the same blocking `_rc = 1` exit as `uncovered`,
  so the same "user pushed through" exception applies structurally — but the only measurement this
  repository has, the frozen corpus baseline (`spec-coverage-scope-baseline.tsv`), finds 24 of 117
  ids UNSCOPED under this scope filter across this repo's own pre-existing plans, none of which
  were written to cite their test files' basenames because the convention did not exist yet before
  this feature. Until plans are routinely written against it, `unscoped` is expected to render
  non-trivially at Gate 5, not near-always-empty like its siblings — it renders exactly like
  `uncovered` does when non-empty, folded into the same `requirement_coverage` line above, never a
  seventh array.

These never gated the transition to this point; this is the human checkpoint where they are
actually read.

**A seventh advisory-schema finding array exists in the same schema: `accessibility_i18n_findings`
(ADR-0066).** It is deliberately **not** part of this six-array roll-up, and unlike `task_metrics`
below, the exclusion here is **structural, not semantic** — it carries a claim about the work
exactly like the other six (`"labels": "fail"` is an assertion, the same shape as a
`suspect_findings` entry), but it is written by **Gate 5.05**, which runs strictly *after* this
`AskUserQuestion` has already rendered, so its data cannot retroactively appear in this text. It
renders its own one-line summary directly at Gate 5.05 instead, the same precedent Gate 5.06's own
severity table already set for a sub-gate reporting on itself rather than being folded backward
into Gate 5. See the Gate 5.05 block below for that render and ADR-0066 §D2 for why it never
blocks either.

**`plan_deviations` is rendered at Gate 5, on its own line, and is NOT the seventh member of the
roll-up (ADR-0073 §D3, issue #178).** The exclusion is semantic, like `task_metrics`' and unlike
`accessibility_i18n_findings`': the six are *findings* — each asserts something may be wrong and
asks whether to run a review cycle. A plan deviation asserts nothing is wrong. It is a declaration
that the implementation departs from the document the human approved at Gate 2, and the decision it
asks for is not "review or not" but "is this departure acceptable". Folding it into a summary about
review-cycle volume would bury exactly the thing that needs reading.

Render it immediately BEFORE the roll-up, and only when non-empty:
`Plan deviations declared by the coder (<N>) — the implementation departs from the approved plan
here:` followed by one line per entry, `task <N>: <constraint> — <action>: <reason>`. When the
array is empty or absent, render nothing at all: a "Plan deviations: none" line on every run is the
padding the roll-up block above already refuses.

**It is a self-report and the render says so**, in one clause: `(declared by the coder; nothing
verifies this list is complete)`. That sentence is what keeps this a disclosure rather than a gate
someone later mistakes for coverage.

**`task_metrics` is not part of this roll-up and is not rendered at Gate 5, or anywhere else, at
all (ADR-0064 §D2, issue #118).** Its exclusion IS semantic — `task_metrics` carries no claim,
only a number, so there is nothing here for a human to decide, at this gate or any other. It is
written to `step5-report.json` for later analysis and read only when someone goes looking.

Use `AskUserQuestion`:
```
question: "Gate 5 — Review cycle (Human approval required)\n\nTasks completed: <N>\nFiles modified: <list>\nTests: <green | red | n/a>\nHarness delta: <if relevant>\n<plan-deviations block, rendered only when non-empty>\n<the advisory roll-up rendered above>\nAnonymize: <ON if manifest.anonymize=true | OFF (default)>\n\nRun a review-triage-fix cycle? Estimated: 5-10 min.\n\nOnly you can decide whether a review cycle is needed."
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

**Record the gate outcome** — see *Gate approval recording* in §5: `~/.claude/skills/concept-to-code/scripts/manifest-set-gate.sh <manifest-path> 5 approved "<run review|skip review>"`. Under autopilot record the default that was taken, so the trail shows the decision was made by the flag rather than by a person.

---

**Gate 5.05 — UI layout audit + accessibility/i18n checklist (conditional, auto-run)**

Trigger: after Gate 5 (review complete or skipped), before Gate 5.1.

Check whether any UI files were modified in this cycle (issue #478, ADR-0160 — a `.swift` file is
UI-bearing only when its own content imports SwiftUI/AppKit/UIKit or declares a `View`/`NSView`/
`UIViewController`-conforming type; the web extensions stay a bare extension match, the shape
`ui-file-detect.sh`'s own header explains):
```bash
git diff --name-only HEAD | bash ~/.claude/skills/concept-to-code/scripts/ui-file-detect.sh
```

- **Output is empty:** emit "Gate 5.05: no UI files changed — skipping layout audit ✓". No
  `accessibility_i18n_findings` entry is written this cycle — the checklist below inherits this
  same UI-file condition rather than adding a second one (ADR-0066 §D4: conditional on UI-bearing
  chains, inert otherwise). Proceed to Gate 5.1.
- **Output non-empty:** emit "Gate 5.05: UI files detected — running ui-layout-audit...". Invoke
  `Skill(skill="ui-layout-audit")`. **Immediately after ui-layout-audit returns (do NOT wait for
  user input),** walk the accessibility/i18n checklist below and record a result.

No AskUserQuestion — the skill auto-applies P1/P2 fixes and reports P3 as recommendations.

**Accessibility/i18n checklist (ADR-0066 §D1/§D3).** Against the same diff `ui-layout-audit` just
reviewed, assess each of the seven named items below and record `pass`, `fail`, or
`not-applicable` with a one-line note:
- `labels` — do interactive elements carry a meaningful accessible label?
- `contrast` — does foreground/background contrast meet a reasonable legibility bar?
- `dynamic-type-or-scaling` — does text respect dynamic type / user scaling instead of a fixed size?
- `keyboard-or-assistive-tech-reachability` — is every interactive element reachable without a
  pointer (keyboard focus order, VoiceOver/screen-reader labeling, or equivalent)?
- `i18n-unicode-multibyte` — does the code handle Unicode and multibyte text rather than assuming
  single-byte ASCII?
- `i18n-no-english-centric-examples` — are examples and test fixtures free of hardcoded
  English-centric assumptions?
- `i18n-no-locale-formatting-assumed` — is date/number/currency formatting not hardcoded to one
  locale's convention?

Write every item to the `accessibility_i18n_findings` array in `step5-report.json`, then emit a
one-line summary directly at this gate — e.g. "Gate 5.05: accessibility/i18n — 5 pass, 2 fail
(labels, contrast) — see step5-report.json for detail ✓". **This records an answer; it does not
block** (ADR-0066 §D2 — a deliberate divergence from the SPEC's "accessibility is a gate, not an aspiration"
wording, disclosed here rather than silently resolved in either direction: every item
above is a model's judgement about its own UI work, the same generator/verifier problem ADR-0049
exists to fix, and blocking on that self-assessment would gate on noise, not signal). Proceed to
Gate 5.1 regardless of any `fail` entries — Gate 5's review decision already happened and there is
no re-review loop here.

**No detector backs this checklist (ADR-0066 §D5).** Contrast ratios need rendering, label
meaningfulness needs judgement, and "English-centric example" is not a grep pattern — a
grep-based accessibility checker would produce confident nonsense. This is the model reading the
diff and recording its own judgement, the same evidence class `checkpoint_reviews` and
`suspect_findings` already accept at this same boundary.

**Scope, stated once so it does not drift into architecture (ADR-0066 §D3).** The i18n items above
catch the systematic omission the SPEC describes — assumed ASCII, assumed English — and nothing
more. **Do not** introduce an i18n framework, a string-catalogue convention, or a locale strategy:
those are a project's own architectural choice, not something this gate imposes.

**[Autopilot default: same conditional logic — auto-run if UI files present, checklist recorded,
never blocking. Emit: "Gate 5.05: autopilot — ui-layout-audit <ran|skipped>, accessibility/i18n
<recorded|skipped> ✓"]**

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

<!-- dispatch-site: gate506-reviewers class=inline exempt: the reviewer agent has no Write tool in its grant so it cannot produce a completion fact, and a missed report here changes no gate decision -->
```
Agent({ subagent_type: "reviewer",
        prompt: "SCOPE: silent-failure-hunter — error handling audit.\nReview the following files for: empty or swallowed catch blocks, ignored return values or Result types, optional chaining masking failures, unhandled Promise rejections, broad exception catches that hide root causes, and error objects logged without actionable context.\nReport only — do not edit any file. Output findings grouped by severity: CRITICAL / IMPORTANT / SUGGESTIONS.\nFiles: <modified-file-list-from-manifest>" })

Agent({ subagent_type: "reviewer",
        prompt: "SCOPE: type-design-analyzer — structural type quality audit.\nReview the following files for: stringly-typed IDs or enums (String where a newtype/wrapper should be used), missing discriminated unions (raw string/int where a sealed type fits), anemic models (pure DTOs with no invariants or behavior), nullable fields that should never be null, weak encapsulation exposing internal state, and protocol/interface misuse.\nReport only — do not edit any file. Output findings grouped by severity: CRITICAL / IMPORTANT / SUGGESTIONS.\nFiles: <modified-file-list-from-manifest>" })
```
Wait for both agents — **and since CC 2.1.232 that is an instruction, not a guarantee** (issue #435,
ADR-0139). Both dispatches return immediately with metadata and their reports arrive as separate
notifications, so this sentence is now load-bearing where it used to be free. It stays an
instruction because the `reviewer` agent's grant carries no `Write` tool
(`staging/plugin/agents/reviewer.md`), so it structurally cannot write a completion fact the way the
Step 5 coder does. What bounds the damage is that this gate produces a report and decides nothing:
merging early loses a finding from a table, it never advances a state or greens a check.

Merge the two finding lists, deduplicate by file+location, then present the aggregated result as a single severity table (CRITICAL / IMPORTANT / SUGGESTIONS). Emit "Gate 5.06: specialized review complete ✓". **Proceed immediately to Gate 5.1 — no additional HITL.**

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

<!-- autopilot-gate-exempt: raises no AskUserQuestion at all — it is a bare state transition, so there is no human decision for autopilot to default -->

Trigger: post Gate 5.1, pre Step 7.

Transition `step_6_review → step_7_commit`. That is the source state whether RTF ran or Gate 5
skipped it — both reach here from `step_6_review`, since Gate 5 is a branch inside that state and
not a state of its own (issue #265, ADR-0105).

> This step is what remains of **Gate 5.5 (humanize deliverables), removed per ADR-0040**. The
> gate listed README, CHANGELOG, ADR prose, `.md` docs and SPEC.md as its targets, and every one
> of those is an internal artifact that no longer takes a humanize pass. Its state transition was
> load-bearing, so it stays here; the humanize action and its `AskUserQuestion` are gone. The
> letter `5.5` is not reused.

---

