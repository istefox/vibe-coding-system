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
4b. **Existing-manifest routing (issue #319, ADR-0109).** A manifest may already sit at today's
   path for this slug. Until this block existed the chain refused it — `manifest-init.sh` exits 2
   saying *use resume*, and Form B's table answers *resume not necessary, continue in current
   session*, **naming a command that does not exist**: the in-session entry point is this form,
   which is what just refused. Run the classifier and route on its token. It reads and routes; it
   never writes, never overwrites, never deletes.

   <!-- fence-contract: c2c-form-a-existing-manifest -->
   ```bash
   # ADR-0133 §D1 (issue #394): the body between the two FENCE_BASH lines runs under BASH, not under
   # the host shell, which is zsh here and differs from bash on word splitting, unmatched globs and
   # `echo` escapes. No `export` prologue — this body binds everything it reads, from the two
   # substituted placeholders. The terminator sits at COLUMN 0 even though this fence is indented
   # inside a numbered list item: an indented terminator is swallowed into the here-document and
   # destroys this fence's exit code silently, which here would turn a TERMINAL refusal into a
   # silent pass. It is not a formatting slip — do not tidy it.
   bash <<'FENCE_BASH'
   _root="<project-root>"; _slug="<topic-slug>"
   # The path is constructed here because it must be known BEFORE manifest-init.sh runs, which is
   # the one thing that construction is for. `manifest-init.sh` computes the same path the same
   # way; if the date rolls between this check and that call, its exit-2 is the backstop, which is
   # why that contract is deliberately left untouched by this feature.
   _man="$_root/docs/manifests/$(date +%Y-%m-%d)-$_slug.manifest.yml"
   _out=$(bash ~/.claude/skills/concept-to-code/scripts/manifest-entry-state.sh "$_man" 2>&1); _rc=$?
   if [ "$_rc" -eq 3 ]; then
     echo "ENTRY-ROUTE: DID-NOT-RUN — $_out"
     echo "  The classifier could not run. Do NOT guess: an unrun check is not a clean result."
     echo "  Run: bash <repo>/staging/sync-to-claude.sh --apply"
     exit 3
   fi
   [ "$_rc" -eq 0 ] || { echo "ENTRY-ROUTE: DID-NOT-RUN — bad invocation: $_out"; exit 3; }
   case "${_out%%|*}" in
     NONE)
       echo "ENTRY-ROUTE: NONE — no manifest for this slug today; proceed to step 5."; exit 0 ;;
     ADOPTABLE)
       echo "ENTRY-ROUTE: ADOPTABLE (${_out#*|}) — adopt this manifest and continue IN THIS SESSION."
       echo "  Do not create a second one. Do not send the operator to resume: this state is"
       echo "  exactly what Form B refuses. Read the manifest, skip to the step it names, continue."
       exit 0 ;;
     BOUNDARY)
       echo "ENTRY-ROUTE: BOUNDARY (${_out#*|}) — Gate 4 was presented and never answered."
       echo "  Re-present Gate 4 in this session. Nothing before Gate 4 needs redoing."
       exit 0 ;;
     RESUMABLE)
       echo "ENTRY-ROUTE: RESUMABLE (${_out#*|}) — planning is done; this is Form B's job."
       echo "  Run: /skill concept-to-code resume $_man"
       exit 0 ;;
     LATE)
       echo "ENTRY-ROUTE: LATE (${_out#*|}) — implementation is past review entry."
       echo "  Continue in this session from that step. Form B has no branch for it."
       exit 0 ;;
     UNRESUMABLE)
       echo "ENTRY-ROUTE: UNRESUMABLE (${_out#*|}) — an express or hybrid chain in flight."
       echo "  Those paths never cross a session boundary, so resume is not an option at all."
       echo "  Continue in this session from that step."
       exit 0 ;;
     TERMINAL)
       echo "ENTRY-ROUTE: TERMINAL (${_out#*|}) — this topic already ran to a terminal state today."
       echo "  STOP. Starting a second chain on the same slug is an explicit human decision:"
       echo "  present it as a gate, or use a different topic slug. Never overwrite the record."
       exit 1 ;;
     UNKNOWN|UNREADABLE)
       echo "ENTRY-ROUTE: ${_out%%|*} (${_out#*|}) — the manifest does not parse, or names a state"
       echo "  the validator does not recognise. STOP and show it to a human; do not route it."
       exit 1 ;;
     *)
       echo "ENTRY-ROUTE: DID-NOT-RUN — unrecognised token '${_out%%|*}'"; exit 3 ;;
   esac
FENCE_BASH
   ```

   **Unattended callers.** What a `autopilot` run does with a non-`NONE` answer was decided by
   ADR-0111 (issue #324), and it is decided in `project-conductor`, not here: a `TERMINAL` token
   marks the feature `[~]` with a reason and the roadmap continues; every other token writes the
   run-level `needs-human` marker and halts the run. The policy lives at the two conductor call
   sites (Step 4's entry-init guard, Step 5 branch C) because only the conductor owns PROJECT.md
   and the roadmap. Do not duplicate it into this block — a second copy is how the two would come
   to disagree about whether a safety marker fires.
5. Run `scripts/gate0-detect.sh <project-root> "<topic-full-title>" "<topic-slug>"`. Read all output fields:
   `spec_adr_exist`, `mode`, `repo_file_count`, `file_vote`, `keyword_vote`, `spec_topic_match`,
   `spec_topic_slug`, `skill_exists`. **Keep `spec_topic_slug`** — it is the slug the EXISTING
   `SPEC.md` claims, and Step 1's archive fence needs it to name the archive (ADR-0096).
   (`topic-slug` is computed at step 2; passing it as arg 3 enables Bug-1 topic-match detection and the skill-exists guard.)

5b. **PROJECT.md — multi-feature project context (optional):**
   ```bash
   _project_md="<project-root>/PROJECT.md"
   ```
   - If `_project_md` exists: read its full content into `$_project_context`. Emit one line:
     `"Project context loaded from PROJECT.md — <N> phases detected."` (count `### Phase` lines).
     Store `_project_context` for injection into Steps 2 and 5.
   - If absent: `_project_context = ""`. Silent — no UX impact.

6. Invoke `~/.claude/skills/concept-to-code/scripts/manifest-init.sh` with args: `topic-slug`, `topic-full-title`, `project-root`, `<mode>` — where `<mode>` is the `mode` field from `gate0-detect.sh` output (`greenfield` or `brownfield`). **NOT** the `chain_path` (`standard`/`express`/`hybrid`) which is determined later at Gate 0.
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
7b. **Unattended routing pre-flight (issue #329, ADR-0115).** Runs for **every** route out of
   step 7 — the Gate 0 click, the Gate 0 autopilot default, and the `express|hybrid|standard`
   prefix fast path that skips Gate 0 altogether. That coverage is the reason it lives at the
   step and not inside the gate: the check it replaces sat inside Gate 0's `[auto]` branch, where
   the fast path bypassed it and the one caller that needs it — an unattended run whose
   `autopilot` was already set by `project-conductor` — never clicked it, so it never ran once.

   This is a **CHECKER**: branch on the exit code. (`weakening-scan.sh`, invoked from `commit`
   Step 1, is a REPORTER — it always exits 0 and signals `CLEAN` on stdout. Do not copy one
   block's branching into the other.) Exit **3** is separate from exit **1** on purpose: a check
   that could not look must not read as a check that found nothing.

   <!-- fence-contract: c2c-autopilot-routing-preflight -->
   ```bash
   # ADR-0133 §D1 (issue #394): the body between the two FENCE_BASH lines runs under BASH, not under
   # the host shell. `export` forwards this body's caller-bound free variables across the new process
   # boundary; a plain shell variable does not survive it. The terminator sits at COLUMN 0 even
   # though this fence is indented inside a numbered list item: an indented terminator is swallowed
   # into the here-document and destroys this fence's exit code silently, which here would turn an
   # ABORT into a pass. It is not a formatting slip — do not tidy it.
   export _root _man
   bash <<'FENCE_BASH'
   # Free variables, bound by the orchestrator: _root (project root), _man (manifest path).
   _c2c="$HOME/.claude/skills/concept-to-code/scripts"
   _mfs="$_c2c/manifest-field-state.sh"
   if [ ! -f "$_mfs" ]; then
     echo "AUTOPILOT-PREFLIGHT: DID-NOT-RUN — field reader missing: $_mfs"
     echo "  Run: bash <repo>/staging/sync-to-claude.sh --apply"
     exit 3
   fi
   # ADR-0076 §THE RULE: read a manifest field through the helper, never with a bare m.get().
   # ABSENT, INVALID and UNREADABLE are three states and this gate must not collapse them.
   # No new dependency class — step 4b of this same form already hard-depends on this script.
   _ap=$(bash "$_mfs" "$_man" autopilot 2>&1) || {
     echo "AUTOPILOT-PREFLIGHT: DID-NOT-RUN — $_ap"; exit 3; }
   case "$_ap" in
     UNREADABLE*)
       echo "AUTOPILOT-PREFLIGHT: DID-NOT-RUN — the manifest does not parse: $_man"; exit 3 ;;
     "PRESENT|True") : ;;
     *)
       # ABSENT or false: an attended run. Byte-for-byte today's behaviour.
       echo "AUTOPILOT-PREFLIGHT: NOT-AUTOPILOT — attended run, nothing to check."; exit 0 ;;
   esac
   _cp=$(bash "$_mfs" "$_man" chain_path 2>&1) || {
     echo "AUTOPILOT-PREFLIGHT: DID-NOT-RUN — $_cp"; exit 3; }
   _cpv="${_cp#PRESENT|}"
   # Every abort transitions the manifest FIRST. Left in flight it reads ADOPTABLE at
   # project-conductor Step 5 branch C and halts the whole roadmap; aborted reads TERMINAL and
   # is a contained per-feature skip — the blast radius ADR-0111 (issue #324) removed.
   case "$_cpv" in
     express|hybrid)
       bash "$_c2c/manifest-transition.sh" "$_man" aborted aborted >/dev/null 2>&1
       echo "AUTOPILOT-PREFLIGHT: ABORT — chain_path is '$_cpv' and autopilot is true."
       echo "  Express step E1 runs plan mode; hybrid step H1 invokes interview-driver"
       echo "  unconditionally. Neither can complete with nobody present. Only standard is"
       echo "  unattended-safe, which is what the [auto] option's own label says."
       exit 1 ;;
   esac
   # A null or absent chain_path PROCEEDS, and the reason is measured rather than assumed: 18 of
   # 41 corpus manifests carry autopilot:true with chain_path:null, all brownfield, all
   # completed. Refusing it would fail the dominant historical shape over a bookkeeping gap in
   # the manifest write, not a routing decision that went wrong.
   if [ ! -f "$_root/SPEC.md" ]; then
     bash "$_c2c/manifest-transition.sh" "$_man" aborted aborted >/dev/null 2>&1
     echo "AUTOPILOT-PREFLIGHT: ABORT — autopilot is true and $_root/SPEC.md does not exist."
     echo "  With no SPEC, gate0-detect.sh reports spec_adr_exist=false, the chain routes"
     echo "  greenfield, and Step 1 dispatches interview-driver — interactive, on a path with"
     echo "  nobody to answer it. Generate the SPEC first (run the chain without autopilot), or"
     echo "  place one at docs/specs/<issue>-*.spec.md for project-conductor to copy in."
     exit 1
   fi
   echo "AUTOPILOT-PREFLIGHT: OK — autopilot, chain_path '$_cpv', SPEC.md present."
   exit 0
FENCE_BASH
   ```

   Branch on the exit code:
   - **`0`** → proceed to step 8. Both the attended no-op and the verified-unattended case.
   - **`1`** → the chain is already transitioned to `aborted`. Stop. An unattended caller reads
     that as a contained per-feature end (`TERMINAL`) and continues its roadmap.
   - **`3`** → the check did not run. Stop **without** transitioning: an unread gate is not a
     clean gate, and guessing here is what issue #329 cost a whole night.

   **`project-conductor`'s just-in-time SPEC copy stays the primary defence for the autopilot
   path** — it settles a missing SPEC before any manifest exists at all, where this fence has to
   create one and then abort it. This is a backstop for every other route to `autopilot = true`,
   including the attended conductor's "Start in autopilot mode", which does not run the SPEC copy.
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
   step_h1_interview` (hybrid) — see the **Gate 0d transition block** at the end of the Gate 0d
   section in §5 for the exact transition, unmodified by this task.

For `chain_path=standard` with `mode=brownfield`, Step 1 is a no-op (§4 Step 1 already handles
this); otherwise execution continues in the matching path's own Step 1 definition (§4 Step 1 /
Step E1 / Step H1), reached via the routing transition in step 8c above.

**Form B — Resume from manifest (use in fresh session after Step 4):**
```
/skill concept-to-code resume <manifest-path>
```
Example: `/skill concept-to-code resume /Users/stefanoferri/Developer/pricing-markup-cli/docs/manifests/2026-05-22-rate-limiter.manifest.yml`

Behavior:
1. Invoke `~/.claude/skills/concept-to-code/scripts/manifest-validate.sh <manifest-path>`. Non-zero exit → abort with parse error.
1b. **Session scope guard (IMPORTANT — runs before any other step):** read `project_root` from the manifest. Resolve the session CWD (`$PWD`). If `project_root` is NOT equal to CWD and is NOT a subdirectory of CWD, abort immediately with:
   > "SCOPE ERROR: manifest project_root (`<project_root>`) is outside this session's working directory (`<CWD>`). This session is scoped to `<CWD>` and must not operate on a different project. Open a new Claude Code session inside `<project_root>` and resume the chain from there."
   Never proceed past this guard on a scope mismatch — not even to read the manifest further.
2. Read `current_step`. Branch:
   - `ready_for_implementation` → run TOFU guard (step 2b below), then evaluate the Step 4.5
     tracer-bullet probe (§4 Step 4.5) if `manifest.tracer_bullet_mode = probe` (no-op if `skip`,
     the default), then proceed to Step 5 dispatch coder.
   - `step_5_implementation` → **a Step 5 that was entered and interrupted.** Run the TOFU guard,
     skip Step 4.5 (it routes out of `ready_for_implementation` and this manifest has left that
     state), and re-enter Step 5 at its recovery-readiness pre-flight. The four assertions are
     re-run in full and Step 5.0.5 is a same-to-same no-op; Step 5.0.3 already refuses to rewrite a
     non-null `recovery_baseline_sha`, so the baseline survives the re-entry (ADR-0050 §D3).
     **This branch exists because of issue #248's fix** (ADR-0095): before Step 5.0.5, a chain sat
     at `ready_for_implementation` for the whole of Step 5 and matched the branch above. Without it
     an interrupted Step 5 matches no branch at all — the fix would have closed a transition hole by
     opening a recovery one.
   - `step_4_session_boundary` → **Gate 4 was presented and never answered.** Re-present Gate 4;
     nothing before it needs redoing. **This branch was missing entirely until issue #319**, and it
     is the one that mattered most: Gate 4's own "Abort chain" message tells the operator to resume
     from this state, and `project-conductor` Step 3 and Step 5 branch B both act on it by invoking
     this form. Three states matched no branch at all; ADR-0095 had disclosed only `step_6_review`.
   - `step_6_review` or `step_7_commit` → **implementation is past review entry.** Re-enter at that
     step in this session. Named here rather than left to fall through the table, which is what
     both did before #319.
   - Any step before `step_4_session_boundary` → refuse, **and name the command that exists**:
     "resume is not the entry point for this state — re-invoke Form A on the same topic
     (`/skill concept-to-code <topic-full-title>`) and its step 4b will adopt this manifest and
     continue in this session." The refusal itself is correct: an interview is not resumable across
     a session boundary. What was wrong for the whole life of this file is that its remedy named no
     command — Form A was the in-session entry point and it refused on file existence (#319).
   - `chain_path` is `express` or `hybrid`, in any non-terminal state → error: "express and hybrid
     chains never cross a session boundary (see *Resume semantics*), so resume is not an option at
     all. Re-invoke Form A on the same topic to continue in this session."
   - `completed` or `aborted` → error: "chain terminated. A second chain on the same slug the same
     day is an explicit decision: use a different topic slug, or start one deliberately tomorrow.
     Form A will not silently create a second manifest, and nothing here overwrites the record."
   - `failed` → error: "chain in failure state, manual recovery required".
3. Update `session_boundary.resumed_at` and `last_updated_at`.

**Step 2b — TOFU guard (resume path only):**

Skip entirely if `manifest.test_cmd_candidate` is null or `NONE`.

Otherwise check trust registration (read-only Bash — safe in auto mode):
```bash
TCF="<project-root>/.claude/test-cmd"
H=$(shasum -a 256 "$TCF" | cut -d' ' -f1)
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
  [OPTIONAL — Step 4.5 tracer-bullet probe, tracer_bullet_mode=probe only (ADR-0057). Inline at
   ready_for_implementation, no dedicated state (same shape as Gate 2b / Gate 5.05 / Gate 5.06):
     verdict=green            → ready_for_implementation → step_5_implementation (unchanged pair)
     verdict=amber            → ready_for_implementation → gate_2_architecture_review (new pair)
     verdict=red, continue    → ready_for_implementation → step_5_implementation (unchanged pair)
     verdict=red, reduce scope→ ready_for_implementation → gate_2_architecture_review (new pair)
     verdict=red, hand-code   → ready_for_implementation → aborted (existing wildcard)]
  [FRESH SESSION]
  → step_5_implementation → step_6_review
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

Legal transition pairs (45 total — 25 standard + 6 express + 14 hybrid, including Gate 0d routing, Step 4.5 tracer-bullet routing, and direct-close shortcuts). Four standard pairs through `gate_5_review_decision` were removed by issue #265 (ADR-0105): nothing ever entered that state, because Gate 5 is an inline sub-gate:
- Standard (preserved): 25 pairs total — the 28 pre-existing pairs, minus the four `gate_5_review_decision` pairs removed by ADR-0105, plus 1 new pair for Step 4.5's
  amber / "red → reduce scope" route (ADR-0057): `ready_for_implementation→gate_2_architecture_review`.
  Green and "red → continue anyway" reuse the existing `ready_for_implementation→step_5_implementation`
  pair; hand-code reuses the existing unconditional any-state-to-`aborted` wildcard. Checked against
  the ADR-0027 Gates-0c/0d lesson (pairs can be written but structurally unreachable) before assuming
  new pairs were needed at all — Gate 2b and Gate 5.05/5.06 are already inline sub-gates with no
  dedicated state, and Step 4.5 follows the same shape, so only this one pair was actually missing.
- Express (new): `step_0_init→step_e1_plan`, `step_e1_plan→step_e2_execute`, `step_e2_execute→gate_e3_verify`, `gate_e3_verify→step_e4_commit`, `step_e4_commit→completed`, `gate_e3_verify→completed`
- Hybrid (new): `step_0_init→step_h1_interview`, `step_h1_interview→gate_h1_spec_review`, `gate_h1_spec_review→step_h2_plan`, `gate_h1_spec_review→gate_h1b_brainstorm`, `gate_h1_spec_review→step_h1_interview`, `gate_h1b_brainstorm→step_h2_plan`, `gate_h1b_brainstorm→gate_h1c_macos_ux`, `gate_h1c_macos_ux→step_h2_plan`, `step_h2_plan→step_h3_execute`, `step_h3_execute→gate_h3_verify`, `gate_h3_verify→step_h4_review`, `gate_h3_verify→step_h5_commit`, `step_h4_review→step_h5_commit`, `step_h5_commit→completed`

**Resume semantics:** Express and Hybrid paths do NOT cross session boundaries. Form B resume is valid only for `chain_path=standard` or `chain_path=null` (legacy). Attempting to resume an express or hybrid manifest emits an error and aborts.

Helper scripts:

> **PATH RULE — all scripts use the absolute prefix `~/.claude/skills/concept-to-code/scripts/`.
> NEVER derive the path from the manifest location (`<manifest-dir>/scripts/` does NOT exist).
> Every bash call below must use the full absolute path.**
>
> Bare mentions: prose may name a helper as a bare code span, e.g. `<helper>.sh`, with no arguments and no path prefix — that is compliant prose, not a call site. A relative `scripts/<helper>.sh`
> path, an unquoted `<helper>.sh` in running text, a name followed by arguments, or a name preceded
> by an invocation verb (via, call, invoke, run, use, execute, …) is read as a call site and must
> carry the absolute prefix above. A line that is genuinely prose in one of those shapes declares a
> `path-rule-exempt` HTML comment on that same line, in the exact form stated in
> `path-rule-check.sh`'s header.

- `~/.claude/skills/concept-to-code/scripts/manifest-init.sh` — creates manifest at `step_0_init` (schema 1.3, adds `chain_path`, `gate0.chain_path`, `gate0.auto_detect_reason`)
- `~/.claude/skills/concept-to-code/scripts/manifest-validate.sh` — validates schema 1.0|1.1|1.2|1.3 + state invariants + optional fields
- `~/.claude/skills/clean-public-repo/scripts/detect-public-remote.sh` — auto-detect public GitHub remote (D1 ADR-0011); output `public|silent`; fail-safe to `silent`. **NB: belongs to the `clean-public-repo` skill, not to `concept-to-code` — use the absolute path.**
- `~/.claude/skills/concept-to-code/scripts/manifest-transition.sh <manifest> <new-step> [<new-status>]` — performs legal state transitions atomically (45 pairs).
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

**Greenfield** — **two different states reach this branch, and only one of them is "no SPEC.md on
disk".** The other is a root `SPEC.md` that exists and belongs to a *different* topic:
`gate0-detect.sh` reports `spec_topic_match=false` and disowns it, which settles **routing** and
nothing else. The file is still sitting at the path the dispatch below writes to (issue #228).

**Archive the outgoing SPEC first (ADR-0096).** Runs before the dispatch, always, on both states —
it is a no-op on the genuinely-empty one.

<!-- fence-contract: c2c-step1-spec-archive -->
```bash
# ADR-0133 §D1 (issue #394): everything between the two FENCE_BASH lines runs under BASH, not under
# the host shell, which is zsh here and differs from bash on word splitting, unmatched globs and
# `echo` escapes. `export` forwards this body's caller-bound free variables across the new process
# boundary. The terminator sits at COLUMN 0 on purpose: an indented one is swallowed into the
# here-document and destroys this fence's exit code silently — and this fence's whole contract is
# its exit code. Do not tidy it.
export ROOT OUT_SLUG
bash <<'FENCE_BASH'
# Free variables, bound by the orchestrator: ROOT (project root), OUT_SLUG (`spec_topic_slug`
# from the gate0-detect.sh run at Gate 0 — the slug the EXISTING SPEC.md claims, never this
# chain's slug).
_sa="$HOME/.claude/skills/concept-to-code/scripts/spec-archive.sh"
if [ ! -f "$_sa" ]; then
  echo "SPECARCHIVE_NOSCRIPT"; exit 3
fi
_out=$(bash "$_sa" "$ROOT" "${OUT_SLUG:-unknown}"); _rc=$?
printf '%s\n' "$_out"
exit "$_rc"
FENCE_BASH
```

Branch on the exit code — this is a **checker**, not a reporter:

- **`0`** (`NOSPEC`, `ALREADY <path>`, `ARCHIVED <path>`) → proceed to the dispatch. On `ARCHIVED`,
  emit one line naming the path, so the archive is visible rather than silent; Gate 4.0 commits it
  with the rest of the planning artifacts.
- **`1`** (`COLLISION <path>`) → **HALT. Do not dispatch.** The archive already holds a different
  file under that name, and overwriting it is issue #228 reproduced inside the directory that exists
  to prevent it. Print: `"Step 1: the outgoing SPEC cannot be archived — <path> exists with
  different content. Compare them (diff SPEC.md <path>), then move or rename one by hand and
  re-invoke."`
- **`3`** → **HALT.** The check did not run, which is not the same as nothing to archive. Print the
  script's stderr and the sync remedy (`bash staging/sync-to-claude.sh --apply`).

Dispatch (unchanged):

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
- Every plan task cites the SPEC requirement IDs it satisfies, form
  `### Task 3 — … (R-02, R-05)` or on a checkbox item; every ID declared by the SPEC must be
  cited by at least one task; never cite an ID the SPEC does not declare.

[IF manifest.anonymize=true — add this block to dispatch, otherwise omit:]
Anonymize mode: ON (ADR-0011). Produce ADR and plan concisely and directly.
No meta-commentary about the tool (e.g., "generated by", AI task references, process narration).
Technical, direct docs — as a senior engineer would write them.

Return a report with: ADR path, plan path, ARCH path (or "n/a"), top 3 key decisions, top 3 risk flags.
Include any `EXTERNAL DEPENDENCY:` lines (ADR-0060) and TEST-CMD CANDIDATE before DURABLE NOTES (see architect.md Output Format).
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
| `EXTERNAL DEPENDENCY:` lines | Lines starting with that literal | none — optional; absent means no dependency declared, not that none exist (ADR-0060 §D5) |
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

#### Proportional audit depth — profile resolution (ADR-0055)

**Single resolution site.** This subsection is the only place in the chain that maps
`manifest.risk` and `manifest.task_type` to an audit profile. Do not restate this mapping at
another call site — a second copy is exactly how `autopilot-build`'s stale restatement of c2c's
own isolation check went stale (ADR-0049 §D5). Step 5 and Step 6 below both point back here
instead of re-deriving the rule.

**Axes and fields (ADR-0055 §D1).** `risk: low|high`. `task_type:
boilerplate|glue|novel-algorithm|regulated|legacy-integration|perf-critical`. Both additive,
conditional-if-present in `manifest-validate.sh`, no schema bump — pre-ADR-0055 manifests stay
valid with no migration.

**Absent means STRICT here, not inert — the opposite default from ADR-0052/0053/0054 (ADR-0055
§D2).** Those three features *add* a constraint, so an absent field means "no new restriction",
which is the pre-feature status quo — inert is safe. This feature *removes* constraints: a `low`
risk `boilerplate` task gets a lighter profile than the chain runs today. If an unset field meant
"no profile applies", every existing manifest would silently downgrade to the lightest audit the
moment this merged. So:

- `risk` absent, `null`, or a pre-ADR-0055 manifest (the field does not exist at all) resolves to
  the **strict** profile.
- `task_type` absent, `null`, or a pre-ADR-0055 manifest also resolves to the **strict** profile.

**Resolution — `max()` across the two axes, never averaged (ADR-0055 §D3).**
- risk axis → `strict` unless `risk` is exactly `low` (in which case → `light`).
- task_type axis → `light` only when `task_type` is exactly `boilerplate` or `glue`; every other
  value (`regulated`, `perf-critical`, `novel-algorithm`, `legacy-integration`) → `strict`.
- `profile = strict` if **either** axis resolves to `strict`, else `light`. The strictest axis
  wins.
- Worked example: `risk: high` with `task_type: boilerplate` resolves to the **strict** profile —
  the `high` risk axis alone forces it, regardless of the lighter task_type.

No averaging, no weighted score, no numeric dial anywhere in this resolution. A numeric score
invites tuning, and tuning a safety profile only ever moves toward "faster" — nobody tunes it back
stricter after a quiet month. Two buckets, `strict` and `light`, combined by `max()`, full stop.

**The floor (ADR-0055 §D4) — depth only, never existence.** A `light` profile may reduce review
passes, skip the optional reviewer lens, or shrink checkpoint cadence (see the two bullets below).
It may **never** remove, skip, or soften any of these four, regardless of the resolved profile:

- `spec-coverage.sh` — Requirement-ID coverage gate, Step 5 → Step 6 (ADR-0048).
- `weakening-scan.sh` — the weakening scan / Anti-test-weakening gate, Step 5 → Step 6 (ADR-0047).
- `interface-check.sh` — Interface immutability gate, Step 6 (ADR-0053).
- the Recovery-readiness pre-flight, Step 5 entry (ADR-0050).

These four run exactly as documented at their own call sites below, unconditionally, with no
`profile` branch anywhere in their own sections. Otherwise the field becomes a bypass with a
friendly name: a `task_type: boilerplate` label on a payment change would disable the checks that
exist for payment changes — and the label is set by the same process being checked.

**What `light` may reduce, concretely:**
- **Checkpoint cadence (Step 5, ADR-0039):** under `strict`, prefer `step5_review_mode: checkpoint`
  when the operator has enabled it; under `light`, `step5_review_mode: none` (the default) is
  sufficient — no per-batch reviewer dispatch is required.
- **Optional reviewer lens (Step 6 Phase 1, `code-review-checklist`):** the Security, Correctness
  and Test coverage categories are never skipped at either profile. Under `light`, the Performance
  category may be abbreviated to a single pass instead of a dedicated deep pass; under `strict`,
  full depth as configured today (unchanged).
- **Review passes:** unchanged by this feature at either profile — Step 6's Phase 1/Phase 4 pass
  structure is untouched; only the per-batch checkpoint cadence above varies.

**Instruction, not enforcement (ADR-0055 consequences).** This subsection is prose a model is
asked to follow. Nothing here blocks a dispatch if the resolved profile is ignored — the harness
pins that the fields, this resolution rule, and the floor all exist; nothing pins that a model
applies the right profile.

### Step 4.5 — Tracer-bullet probe (optional, default skipped; dispatch `coder` agent)

**Trigger:** post Gate 4, at `ready_for_implementation`, before Step 5's dispatch-mode selection —
reached identically whether Gate 4 was "Implement now" (same session) or a Form B resume after
`/clear` (§2 Form B). Runs inline, with no dedicated `current_step` state, the same shape as Gate 2b
(TOFU) and Gate 5.05/5.06 (both inline sub-gates within their enclosing step).

**Optional, off by default (ADR-0057 §D1) — the opposite default direction from ADR-0055 §D2, in
contrast: that feature REMOVES a constraint and so must default strict; this feature ADDS a step,
so absent/`skip` must equal the pre-feature behaviour exactly.** Check `manifest.tracer_bullet_mode`:

- **`skip` (default; absent also means skip):** emit nothing extra. Transition
  `ready_for_implementation → step_5_implementation` exactly as before this feature existed — zero
  behavior change on every chain that does not opt in. Proceed to Step 5.
- **`probe`:** run the probe below. There is no dedicated `AskUserQuestion` to opt in — flip it with
  a manual `sed` before Gate 4, the same idiom as `step5_review_mode` (ADR-0039 §D8), not a new gate:
  ```bash
  sed -i.bak 's/^tracer_bullet_mode: skip$/tracer_bullet_mode: probe/' <manifest>
  ```

**The slice (ADR-0057 §D1, "a judgement call, made by the architect").** The orchestrator never
invents a slice independently of the approved plan: dispatch the plan's task explicitly headed
`Tracer-bullet slice` if the architect (Step 2) included one, else the plan's own first task. The
slice must be **end-to-end**, not a single layer probed deeply — the thinnest journey through every
layer the feature touches, shallowly, because integration is where feasibility actually fails and a
deep single-layer slice only tests what the plan already assumed.

**Budget and attempt cap (§D4 — reuses ADR-0052's mechanism, not a second cost control).** Before
dispatch, write a one-task synthetic plan fragment so `diff-budget-check.sh` can be reused exactly
as Step 5 already uses it:
```bash
cat > "<manifest-dir>/.tracer-bullet-plan.md" <<'EOF'
# Tracer-bullet probe

- [ ] **Task 1 — tracer-bullet slice.** Budget: <declared-files-from-the-slice-task> (~150 lines)
EOF
```
The hard attempt cap is **2 attempts**. **Exceeding either the budget or the attempt cap is itself
evidence, not a reason to keep spending** — a slice that will not converge cheaply is an `amber` or
`red` signal on its own (§D4).

**Dispatch (single coder, model pinned explicitly — ADR-0018 addendum, ADR-0049 §D6).**

The Agent tool takes no effort-level parameter of any kind — the Workflow-only `opts` field that
name would suggest exists on the `agent()` call, lowercase, only (ADR-0068 §D7). Do not add one
here.

```
Agent({ subagent_type: "coder", model: "sonnet",
        prompt: "TRACER-BULLET PROBE (Step 4.5, ADR-0057). Implement ONLY <slice-task-description>
from the plan at <plan-path> — the thinnest END-TO-END slice through this feature: touch every
layer it needs, shallowly, never a single layer probed deeply. Budget: <declared-files> (~150
lines) — stay inside it; if you cannot, stop and report rather than expanding scope. Hard attempt
cap: 2 attempts — if the slice does not converge in two attempts, stop and report what failed
rather than trying a third approach. State explicitly in your report: (1) whether it builds/runs,
(2) whether its own test passes, (3) how many attempts it took, (4) whether you deviated from the
plan's stated approach and why, (5) your own recommended verdict (green/amber/red) — this
recommendation is recorded but is NOT authoritative. Do not commit." })
```

**The verdict is computed, not asked (§D3 — the assertion that matters most in this file).** Treat
the coder's report as CONTEXT ONLY. Compute `tracer_bullet_verdict` from these mechanical facts,
never from the coder's self-assessment:

1. Did the slice build/run at all?
2. Did its own test pass (if a trusted test-cmd exists; a build-only check otherwise)?
3. Attempt count, recorded in `tracer_bullet_attempts`.
4. Did it touch files outside its declared scope? Run:
   ```bash
   # --stat=999, never a bare --stat: git elides a long path to `.../tail` at the default 80-column
   # width, and an elided name is compared against the declared file set as-is (ADR-0070 §D5).
   git diff --stat=999 "$BASELINE_COMMIT" | bash ~/.claude/skills/concept-to-code/scripts/diff-budget-check.sh \
     --plan "<manifest-dir>/.tracer-bullet-plan.md" --tasks 1
   ```
   Parse `BUDGET`/`SCOPE` lines per the reporter contract stated at diff-budget-check.sh's own
   header — never `[ -n "$out" ]` (true even on `CLEAN`), never a bare `grep -c` fallback.

Derivation:
- **`red`** — did not build/run, OR its test failed after the attempt cap (2) is reached.
  Mechanical, not a mood.
- **`green`** — built/ran, test passed, no `SCOPE` finding, no `BUDGET` overshoot, attempts within
  the cap.
- **`amber`** — everything else: passed but with a `SCOPE` finding, a `BUDGET` overshoot, attempts
  at the cap before it passed, or the coder's own report of a deviation from the plan's stated
  approach.

Record the coder's own recommendation verbatim in `tracer_bullet_recommendation` (bash sed, on the
additive field). **The recommendation cannot upgrade a mechanically failing slice to green** — a
coder reporting "I believe this works" over a nonzero test-cmd exit code still computes to `red`.
The narrative is context only, never authoritative; record it, never branch on it.

```bash
sed -i.bak 's/^tracer_bullet_verdict: null$/tracer_bullet_verdict: "<green|amber|red>"/' "<manifest>"
sed -i.bak 's/^tracer_bullet_recommendation: null$/tracer_bullet_recommendation: "<coder-verdict>"/' "<manifest>"
sed -i.bak 's/^tracer_bullet_attempts: 0$/tracer_bullet_attempts: <N>/' "<manifest>"
```

**Routing (all three verdicts, ADR-0057 §D2):**
- **`green`** — emit "Step 4.5: green ✓ — slice kept as the Step 5 pattern seed, proceeding.". No
  `AskUserQuestion` — computed, not asked (§D3). On `green`, the slice is the **pattern seed
  (§D5) and is kept**: do not `git checkout`/revert its files. They stay in the working tree exactly
  as everything else in Step 5 stays uncommitted until Step 7 — no new commit boundary is
  introduced here. Transition `ready_for_implementation → step_5_implementation` (the existing,
  unmodified pair).
- **`amber`** — emit "Step 4.5: amber — <reason> — returning to Gate 2 for scope reduction ✓".
  Transition `ready_for_implementation → gate_2_architecture_review`. No `AskUserQuestion` here —
  Gate 2's own existing block (§5 Gate 2) is what re-presents to the human, which is where the scope
  is actually revised.
- **`red`** — emit "Step 4.5: red — <reason>.". Present **Gate 4.5** (§5 Gate 4.5 block) — `red` is
  the outcome this feature exists for, and the only one that gets a human decision gate.

### Step 5 — Implementation (dispatch `coder` agent, post-resume)

#### Recovery-readiness pre-flight (ADR-0050, before any dispatch)

Four assertions, run once, at the very top of Step 5 — before dispatch-mode selection, before the Smoke test gate below (which itself dispatches a workflow coder), and before the tester stage ADR-0049 introduced further down. At Step 5 entry the tree must already be clean, so that everything the tester dirties afterward is provably Step 5's own doing.

**ADR-0050 §D4 — the reconciliation, updated by ADR-0068 §D6.** This pre-flight guards entry to Step 5, before anything in Step 5 has executed: a dirty tree here is uncommitted human work of unknown provenance, so it refuses to dispatch. ADR-0049 §D2's dirty-tree condition, which used to guard each coder dispatch *inside* Step 5 by tolerating a tree the tester stage had deliberately left dirty and dropping isolation to a second, worktree-less mode, is retired: the tester now runs in its own worktree and its output is committed and merged into the feature branch before the coder's worktree is created (ADR-0068 §D6), so the condition it tested for cannot arise. The two conditions were sequential, not contradictory, while both existed; the surviving invariant is narrower and is what replaces them both: at Step 5 entry the tree is clean, and every stage's output is committed and merged before the next stage's worktree is created.

**Step 5.0.1 — Working tree clean, APART FROM THE MANIFEST (ADR-0050 §D2, amended by issue #239).**

<!-- fence-contract: c2c-step5-preflight-dirty-classify -->
```bash
# ADR-0133 §D1 (issue #394): everything between the two FENCE_BASH lines runs under BASH, not under
# the host shell, which is zsh here and differs from bash on word splitting, unmatched globs and
# `echo` escapes. `export` forwards this body's caller-bound free variables across the new process
# boundary; a plain shell variable does not survive it. The nested `DIRTY_EOF` here-document below
# is unaffected — the outer delimiter is matched only by a line reading exactly FENCE_BASH, so the
# inner one reaches bash intact. The terminator sits at COLUMN 0 on purpose: an indented one is
# swallowed into the here-document and destroys this fence's exit code silently, which here would
# read as a clean tree. Do not tidy it.
export MANIFEST SPEC ADR PLAN CLAUDE_PLUGIN_ROOT
bash <<'FENCE_BASH'
# Free variables, bound by the orchestrator before this block runs:
#   MANIFEST        absolute path to the manifest (the value manifest-init.sh printed)
#   SPEC ADR PLAN   absolute paths from manifest.artifacts.*; ADR/PLAN may be empty on Express
# Exit contract: 0 = clean, proceed to 5.0.2 · 1 = refuse to dispatch · 3 = the check DID NOT RUN.
# The third exists for the same reason it does in spec-coverage.sh and plan-tasks.sh: a checker
# that could not run must not be readable as a checker that found nothing.
_top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "PREFLIGHT_NOREPO"; exit 3; }
[ -n "${MANIFEST:-}" ] || { echo "PREFLIGHT_NOMANIFEST"; exit 3; }
# repo-rel-path.sh ASKS GIT for the repo-relative path. It does not compare strings, and that is
# the whole point: every string form of this comparison has a normalisation it does not perform.
#
# The first draft compared `git rev-parse --show-toplevel` (resolved) against the caller's path
# (not), so `rel()` shortened nothing and EVERY artifact classified as OTHER — including the
# manifest, which made the exemption silently inert. #239 fixed that by resolving both sides with
# `cd … && pwd -P`. That closed the symlink half only: **`pwd -P` resolves symlinks, it does not
# normalise case.** APFS is case-insensitive and case-preserving, so `cd /Users/x/developer/…`
# succeeds and reports the casing you traversed, while git reports the casing it recorded — the
# prefix match failed again, on the same file, for a different reason, and the exemption was inert
# on every run from a differently-cased CWD (issue #344, found by running the chain, twice over).
#
# Deriving the prefix from git removes the comparison rather than correcting it, so there is no
# third normalisation left to miss. The `-ef` guard is device+inode identity — "is this the same
# directory" answered without going back through a string compare, which is the trap being removed.
# It is what keeps an artifact living in a DIFFERENT repository from being handed that repository's
# prefix and silently exempted. Pinned by `recovery-preflight.test.sh` RJ9 (symlink), RJ13/RJ13b
# (case) and RJ14 (foreign repo) through this fence, and by its RRP section directly.
#
# The logic lives in repo-rel-path.sh rather than in a function here because this fence is
# RENDERED before the model executes it, and the renderer substitutes the skill's own invocation
# arguments into the parameter that function read — so what ran was a normalisation whose input
# had been replaced by an unrelated word, reintroducing #239 at render time inside the very block
# written to fix it (issue #385, ADR-0132 §D1). A file is never rendered. Resolved ONCE here,
# above the first of the four calls below; an unresolved helper is the check DID NOT RUN, never a
# clean tree.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] \
   && [ -f "$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/repo-rel-path.sh" ]; then
  _rrp="$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/repo-rel-path.sh"
elif [ -f "$HOME/.claude/skills/concept-to-code/scripts/repo-rel-path.sh" ]; then
  _rrp="$HOME/.claude/skills/concept-to-code/scripts/repo-rel-path.sh"
else
  echo "PREFLIGHT_NOHELPER"
  echo "  repo-rel-path.sh is not deployed. Run: bash <repo>/staging/sync-to-claude.sh --apply"
  exit 3
fi

# The manifest leaves the dirty set BEFORE anything is classified. Do not put it back — see the
# paragraph below this fence for why, and read #239 before deciding the exemption looks careless.
DIRTY=$(git status --porcelain | sed 's/^...//' | grep -vxF "$(bash "$_rrp" "$_top" "$MANIFEST")" || true)
[ -n "$DIRTY" ] || { echo "PREFLIGHT_CLEAN"; exit 0; }

SPEC_REL=$(bash "$_rrp" "$_top" "${SPEC:-}")
ADR_REL=$(bash "$_rrp" "$_top" "${ADR:-}")
PLAN_REL=$(bash "$_rrp" "$_top" "${PLAN:-}")
CHAIN=""; OTHER=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in
    "$SPEC_REL"|"$ADR_REL"|"$PLAN_REL"|CLAUDE.md) CHAIN="$CHAIN$f " ;;
    *) OTHER="$OTHER$f " ;;
  esac
done <<DIRTY_EOF
$DIRTY
DIRTY_EOF

if [ -n "$CHAIN" ] && [ -n "$OTHER" ]; then echo "PREFLIGHT_BOTH chain: $CHAIN| other: $OTHER"; exit 1
elif [ -n "$CHAIN" ]; then echo "PREFLIGHT_CHAIN $CHAIN"; exit 1
else echo "PREFLIGHT_OTHER $OTHER"; exit 1
fi
FENCE_BASH
```

**Why the manifest is exempt, and why removing the exemption breaks every run (issue #239).** The
chain writes the manifest at every state change, and two of those writes land between Gate 4.0's
commit and this assertion: `manifest-set-flag.sh <m> autopilot true` and `manifest-transition.sh <m> <!-- path-rule-exempt: names which two manifest writes land here rather than instructing; one marker covers both occurrences on this line -->
ready_for_implementation`. On the fresh-session branch it is worse — Form B resume step 3 updates
`session_boundary.resumed_at` unconditionally, after any commit the old session could have made, so
no ordering avoids it. Then 5.0.3 below writes `recovery_baseline_sha` into the same file **on
purpose**, three assertions later. "The working tree is clean" and "the manifest is written at every
state change" are flatly incompatible requirements on the same file; the pre-flight asserted one
while the state machine implemented the other, so this assertion had never been satisfied by a real
chain run. ADR-0050 §D2's purpose survives intact: it refuses on work of **unknown provenance**, and
the manifest's provenance is the most known thing in the repository, since the chain is its only
writer. `SPEC.md`, the ADR and the plan stay in the set, so the check this assertion exists for is
unchanged. Reordering Gate 4.0 was considered and rejected: it fixes the in-session branch and
cannot fix the resume branch at all.

**The exemption is bounded by a validity check, not by trust.** Excluding the file from the dirty
set would otherwise let a hand-edited manifest through — and ADR-0075 measured hand-edits as real,
not hypothetical. So run the validator that actually applies to that file, on both Gate 4 branches
(Form B resume already does this at its step 1; the in-session branch never did):
```bash
bash ~/.claude/skills/concept-to-code/scripts/manifest-validate.sh "<manifest>"
```
Non-zero → refuse to dispatch and print the validator's own stderr verbatim. What is exempt is the
manifest's **dirtiness**, never its **content**.

**Remediation, keyed to the token the fence printed:**

- **`PREFLIGHT_CHAIN`** → a chain artifact is uncommitted: the producer did not run, or ran and was
  declined. Print: "Recovery-readiness pre-flight: the chain's own planning artifacts are
  uncommitted. Gate 4.0 should have committed them. Run `/skill commit '<topic> — planning
  artifacts' --no-pr`, then re-invoke Step 5." **Never advise `git stash` here**: `-u` would stash
  `SPEC.md`, the ADR and the plan, which are exactly what the coder and tester dispatches read,
  producing a Step 5 that runs against missing inputs. Until ADR-0071 this was the printed advice,
  and it was wrong on the only path that ever reached it.
- **`PREFLIGHT_OTHER`** → this is the deliberately-dirty resume ADR-0050 §D2 negative consequence 2
  describes. Print: "Recovery-readiness pre-flight: working tree has uncommitted changes unrelated
  to the chain. Run `git stash push -u -m 'c2c-step5-preflight'` (or commit them) and re-invoke
  Step 5."
- **`PREFLIGHT_BOTH`** → prescribe the commit first, then the stash, in that order, and say why:
  committing the artifacts is what makes the stash safe.
- **`PREFLIGHT_NOREPO` / `PREFLIGHT_NOMANIFEST` / `PREFLIGHT_NOHELPER` (exit 3)** → the check did
  not run. Refuse to dispatch and say so in those words. Do not report it as a clean tree.
  `PREFLIGHT_NOHELPER` means `repo-rel-path.sh` is not deployed, and it prints its own remedy: run
  `bash <repo>/staging/sync-to-claude.sh --apply`, then re-invoke Step 5. This gate is worse than
  inert until that sync — an un-synced machine refuses **every** Step 5 rather than mis-classifying
  one, which is the right direction and still a new failure (ADR-0132 §Consequences).

Known limits, stated rather than discovered later: the fence reads porcelain v1, so a **renamed**
chain artifact arrives as `old -> new` and classifies as `OTHER`, and a path containing a space or
a quote is quoted by git and will not match. Neither shape occurs for the four artifacts this
classifies, and `*.bak` is gitignored, so 5.0.3's `sed -i.bak` debris is invisible to both this
fence and to the merge-back escape check (ADR-0068 §D11) — a fact that is load-bearing for both and
was verified, not assumed.

**Step 5.0.2 — A feature branch is checked out, not the default branch.**
```bash
git symbolic-ref --short HEAD
```
Resolve the remote's default branch — do not hardcode `main`:
```bash
git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'
```
If that prints nothing (no remote, or the local symref cache is missing), fall back to:
```bash
git remote show origin 2>/dev/null | sed -n 's/^ *HEAD branch: //p'
```
If both are empty, fall back to the literal `main` — documented here, never a silent hardcode. If the checked-out branch equals the resolved default → refuse to dispatch. Print the literal remediation command: "Recovery-readiness pre-flight: HEAD is on `<default>`, the default branch. Run `git checkout -b feat/<slug>` and re-invoke Step 5." Do not proceed to dispatch-mode selection.

**Step 5.0.3 — HEAD sha recorded as the recovery baseline.**
```bash
git rev-parse HEAD
```
Record as `BASELINE_COMMIT`. Write it once to the manifest via bash sed substitution on the additive field (NOT via Edit tool, NOT via `manifest-set-flag.sh`, which is boolean-only): <!-- path-rule-exempt: negated -- tells the reader NOT to use this helper for this write, never invokes it -->
```bash
sed -i.bak 's/^recovery_baseline_sha: null$/recovery_baseline_sha: "<BASELINE_COMMIT>"/' "<manifest>"
```
If `manifest.recovery_baseline_sha` is already non-null (a resumed Step 5 run), skip the write — it is written once, at pre-flight, and never rewritten by a later step. A baseline that moves is not a baseline (ADR-0050 §D3).

**On that resumed-run branch, check the recorded baseline is still reachable (issue #244,
ADR-0103).** §D3 guarantees the *field* does not move; it never guaranteed the *history under it*
does not. Measured on this repository's two recorded baselines, one is already orphaned — the one
whose chain was paused.

<!-- fence-contract: c2c-step5-baseline-ancestry -->
```bash
# ADR-0133 §D1 (issue #394): the body between the two FENCE_BASH lines runs under BASH, not under
# the host shell. No `export` prologue — this body binds everything it reads, from the substituted
# `<baseline>` placeholder. Terminator at COLUMN 0; an indented one is swallowed into the
# here-document and destroys this fence's exit code silently.
bash <<'FENCE_BASH'
git rev-parse --git-dir >/dev/null 2>&1 || { echo "BASELINE_NOREPO"; exit 3; }
_b="<baseline>"
[ -n "$_b" ] || { echo "BASELINE_NOREPO"; exit 3; }
if ! git cat-file -e "$_b" 2>/dev/null; then
  echo "BASELINE_GONE $_b"
elif git merge-base --is-ancestor "$_b" HEAD 2>/dev/null; then
  echo "BASELINE_OK $_b"
else
  echo "BASELINE_ORPHANED $_b"
fi
exit 0
FENCE_BASH
```

**This is a report, not a halt**, and the distinction is the decision: the run is not damaged, only
its recovery path is, so stopping a healthy chain over a dead baseline would trade a working run for
a hypothetical one. Render whichever line applies and proceed:

- `BASELINE_OK` — say nothing.
- `BASELINE_ORPHANED <sha>` — *"Recovery baseline `<sha>` is no longer an ancestor of this branch
  (the branch was rebased). The object survives in the reflog only, so it is one `git gc` from
  being unrecoverable. A recovery reset to it would detach from this branch's history. Find the
  equivalent commit with `git log --format='%H %s' | grep <subject>` before relying on it."*
- `BASELINE_GONE <sha>` — the same, plus: the object no longer exists at all and there is nothing to
  reset to.
- exit 3 — the check did not run. Say so; do not report a clean baseline.

**The operational rule, which nothing stated before #244: merge `main` into the feature branch; do
not rebase it, once `recovery_baseline_sha` is set.** A merge preserves the recorded commit as an
ancestor and the baseline stays meaningful; a rebase orphans it. This matters because the sequence
that triggers it is the normal one, not an exotic one — Step 5 records the baseline, something halts
the run, fixing the blocker means a PR to `main`, and resuming means bringing the branch up to date.

**The field is never corrected to match reality**, even when this check says it is orphaned. §D3's
write-once rule is worth more than any single record, and a baseline that gets "fixed" whenever it
looks wrong is a baseline again only in name.

**Step 5.0.4 — `worktree.baseRef` is `"head"` in the effective `settings.json` (ADR-0068 §D1, R-05).**
```bash
python3 -c "import json,os,sys; p=os.path.expanduser('~/.claude/settings.json'); d=json.load(open(p)); sys.exit(0 if d.get('worktree',{}).get('baseRef')=='head' else 1)"
```
Non-zero — including a missing or unparseable `settings.json` — counts as **not verified**. **This assertion fails closed**, and that is deliberate: every hook in this repository follows the opposite convention, allow-on-every-failure-mode, so a reader who pattern-matches on that convention will guess this one should fail open too and "fix" it into doing so. It does not, because it is a pre-flight assertion, not a hook, and it sits beside ADR-0050's other three assertions above, which also fail closed. On refusal, print the literal remediation: "Recovery-readiness pre-flight: set "worktree": { "baseRef": "head" } in ~/.claude/settings.json and re-invoke Step 5. Without it every modification agent's worktree forks from the default branch and cannot see this feature branch's commits (ADR-0068 F15)." Do not proceed to dispatch-mode selection. On success, record `bash ~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh <manifest> worktree_baseref_verified true`; on refusal, leave it at the `manifest-init.sh` default of `false`.

**Autopilot (`manifest.autopilot = true`) refuses identically — no leniency branch (ADR-0050 §D6).** A dirty tree, a default-branch checkout, or an unverified `worktree.baseRef` halts the unattended path exactly as it halts the attended one. There is no `AskUserQuestion` on this path, so the remediation command above is recorded in the report rather than prompted to a terminal nobody is watching.

**Step 5.0.5 — enter `step_5_implementation` (issue #248, ADR-0095). Runs only after all four
assertions above have passed, and is the LAST thing before dispatch-mode selection.**

```bash
bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh "<manifest>" step_5_implementation
```

This is the chain's only unconditional producer of that state, and without it Step 5 can be entered
but never left: every "transition to `step_6_review`" further down needs `step_5_implementation` as
its source, and the manifest was still at `ready_for_implementation`. Step 4.5's `green` branch also
performs this transition, but Step 4.5 runs only when `tracer_bullet_mode = probe` and
`manifest-init.sh` writes `skip`, so on a default run nothing performed it at all.

**Running after Step 4.5 is a no-op, not an error** — `manifest-transition.sh` returns 0 on a
same-to-same call. That is what lets both producers coexist instead of one having to guard against
the other; do not add a conditional here.

**Placement is load-bearing in the other direction too.** Every refusal above prints "Do not proceed
to dispatch-mode selection" and leaves the manifest at `ready_for_implementation` — the state a Form
B resume is defined for. Transitioning earlier would strand a refused pre-flight in a state its own
recovery path does not accept.

#### Pattern seed handoff (ADR-0057 §D5, only if Step 4.5 ran and computed `green`)

If `manifest.tracer_bullet_verdict = green`, every coder brief dispatched below — Workflow path and
Agent-tool fallback alike — for a task touching the same layer(s) the tracer-bullet slice touched
MUST add one line: `"Follow the pattern already established in <tracer-bullet slice file list>
(Step 4.5 tracer-bullet probe) — do not re-derive the approach from scratch."` This is the single
resolution site for that instruction, stated once here so both dispatch branches below honor it
without a second copy going stale independently — the same convention `#### Proportional audit
depth` above already uses for its own single resolution site (ADR-0049 §D5 precedent). If
`tracer_bullet_verdict` is `null`/absent (Step 4.5 skipped or not yet run), this subsection is a
no-op.

**Dispatch mode selection:**
- If `manifest.hook_verified = true`: use Workflow dispatch path (below).
- If `manifest.hook_verified = false` or `null` (field absent): present smoke test gate (see
  "Smoke test gate" block below) and STOP until user records result.
- If Dynamic Workflows is unavailable or the `ultracode` keyword (renamed from `workflow` in CC v2.1.160) does not trigger script generation:
  fall back to Agent-tool batch dispatch (see "Fallback — Agent-tool batch dispatch" below).
  Set `step5_mode: "agent_batch"` via bash sed substitution (same as the fallback section below).

**Pre-dispatch: worktree isolation check (the git-dir check runs ONCE before any dispatch, before
dispatch-mode selection and before every stage in every task group below):**
```bash
git rev-parse --git-dir 2>/dev/null
```
The worktree is created from the CWD of the session, not from `project_root` — check the CWD,
not `project_root`. If the CWD is not inside a git repo the worktree will fail even if
`project_root` has its own `.git`.
- exit 0 → CWD is inside a git repo → dispatch coder **with** `isolation: worktree`. There is no
  second mode (ADR-0068 §D1, §D10).
- exit non-0 → refuse to dispatch. Print the literal message: "Worktree isolation contract: the
  session CWD is not inside a git repository. The chain cannot dispatch a modification agent
  here. Run the chain from inside the repository, or `git init` the project root, and re-invoke
  Step 5." Do not proceed to dispatch-mode selection.

**Pre-dispatch: artifact existence check (run before any dispatch):**
```bash
test -f "<manifest.artifacts.adr>"  || echo "MISSING_ADR"
test -f "<manifest.artifacts.plan>" || echo "MISSING_PLAN"
```
If either path is missing on disk: do NOT dispatch coder. Present to user:
> "Artifact not found: `<missing path>`. Architect may have truncated before writing the file. Re-run architect dispatch (Step 2) or restore the file manually."

**Pre-dispatch: plan structure validation (run after existence check):**
<!-- fence-contract: concept-to-code-step5-plan-structure -->
```bash
# ADR-0133 §D1 (issue #394): the body between the two FENCE_BASH lines runs under BASH, not under
# the host shell, which is zsh here and differs from bash on word splitting, unmatched globs and
# `echo` escapes. No `export` prologue — this body has no free variables; the plan path arrives as a
# substituted placeholder. Terminator at COLUMN 0; an indented one is swallowed into the
# here-document and destroys this fence's exit code silently.
bash <<'FENCE_BASH'
# plan-tasks.sh owns the definition of a plan task (ADR-0069 §D1/§D3, issue #172). Do NOT inline a
# grep here: the architect is allowed BOTH `### Task 3 — …` headings and `- [ ]` checkbox items
# (architect.md Output Format); a checkbox-only count rejects 9 of the 62 plans in the corpus
# (re-measured 2026-08-03, ADR-0121), and three files each holding their own answer is the defect
# #172 was filed about.
# This is a CHECKER — branch on its exit code. The anti-test-weakening scan four blocks below and
# the diff-budget reporter are the opposite contract (always exit 0, signal on stdout, print
# CLEAN). Do not copy one block's branching into the other.
# The trailing `# plan-tasks-question:` comment on each invocation declares which question it
# answers; mode-binding-check.sh compares that declaration against plan-tasks.sh's own
# mode-contract table, never against this prose (issue #294, ADR-0131).
tasks=$(bash ~/.claude/skills/concept-to-code/scripts/plan-tasks.sh --count "<manifest.artifacts.plan>")   # plan-tasks-question: guard
rc=$?
openers=$(bash ~/.claude/skills/concept-to-code/scripts/plan-tasks.sh --count-openers "<manifest.artifacts.plan>")   # plan-tasks-question: arithmetic
orc=$?
FENCE_BASH
```

**This fence carries no ADR-0133 §D4 print, and that is a stated exception rather than an
oversight.** Under the wrapper `$tasks`, `$rc`, `$openers` and `$orc` do not survive the terminator,
so the four paragraphs below — and the batch-dispatch policy further down, which reads `$openers` —
name values the orchestrator must carry from this block's own run, exactly as it carries
`<manifest.artifacts.plan>` into it. The §D4 remedy is normally a printed token; here it is not
available, because this block's stdout is asserted BYTE-EXACTLY by an existing execution
(`plan-task-count.test.sh`, section PTF, compares the whole of it against `tasks=[N] rc=[N]`), and a
new line would break a green assertion to satisfy a convention. Read the two counts off this block's
own invocation; do not add a print here without moving that assertion first.

**Two counts, two questions, and using one for the other is issue #242 (ADR-0100).** `$tasks` is
the loose predicate and answers *"is there any task at all"* — it is for the `>= 1` guard below and
for nothing else. `$openers` is the strict predicate and answers *"how many task blocks are there"*
— it is for the batch-dispatch policy in the Agent-tool fallback and for nothing else. Measured
over the 58 corpus plans, the two differ on 51, all of them `>= 6` and over-counted; on #222's plan
they are 38 and 7, and batches of 2-3 over 38 dispatch against tasks that do not exist. **Do not
substitute one for the other in either direction.**
If `rc = 2` or `rc = 3`: do NOT dispatch coder — **the check did not run**, which is not the same as
finding no tasks. Report the script's stderr verbatim and stop.

If `tasks = 0`: do NOT dispatch coder. Present to user:
> "Plan at `<manifest.artifacts.plan>` contains no recognisable task. A task is either a `## Task N — …` heading (H2–H4) or a `- [ ]` checklist item. Open the plan, verify the task list, and re-invoke Step 5."

**Pre-dispatch: anti-test-weakening baseline mark (ADR-0047):**
```bash
_pre5=$(git rev-parse HEAD 2>/dev/null)   # anti-test-weakening gate baseline (ADR-0047)
_pre5_ts=$(date -u +%s)                   # elapsed_wall_seconds baseline (ADR-0064, issue #118)
```
An empty `_pre5` (no commits yet, or the CWD is not a git repository) makes the later
`git diff "$_pre5"` empty, which the scan reports as `CLEAN` — never an error. If `_pre5_ts` is
never recorded (e.g. a resumed session that skipped this block), the Task-level metrics block
below omits `elapsed_wall_seconds` for the rest of this run rather than measuring from an
arbitrary later point.

#### Smoke test gate (pre-dispatch, blocks if hook_verified = false)

If `manifest.hook_verified = false` or `null` or the field is absent from the manifest:

Run the deterministic check. Do NOT ask the user to watch the terminal: a hook that never fired and a
hook that fired and stood down look identical on screen. `pre-flight-pattern-enforce.sh` records every
decision it makes to its own audit log, and that log is the evidence.

> **The path below is the DEPLOYED one and is deliberately not the staging shape** (issue #212).
> `hook-verify-workflow.sh` is vendored flat at `staging/plugin/scripts/`, by ADR-0016 and ADR-0024;
> `sync-to-claude.sh`'s PAIRS remaps it into `skills/concept-to-code/scripts/` on deploy. So
> `staging/plugin/skills/concept-to-code/scripts/hook-verify-workflow.sh` does not exist, and a path
> check run against staging reports it as missing — correctly, and harmlessly. Do not "fix" this
> reference to a staging-shaped path: it would read a file sync never writes there.

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
- **exit 3 (INCONCLUSIVE)** → record NOTHING, do not call `manifest-set-flag.sh`. Either the audit log <!-- path-rule-exempt: negated -- instructs skipping this helper on the INCONCLUSIVE branch, not invoking it -->
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
`hook_verified = false` via `~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh` and take the Agent-tool fallback. Emit:
"Step 5: autopilot — workflow smoke test skipped, using <workflow|fallback> ✓". This prevents an
unattended run from stalling on the smoke-test prompt, and never takes the Workflow path unless hooks
were already verified true.]**

#### Workflow dispatch path — Step 5 implementation (hook_verified = true)

**CONSTRAINT — NO inline source code in the generated workflow script:**
Agent prompt strings in the JS workflow script MUST reference files by path only — never inline raw source code blocks. Embedding language-specific generics (e.g. `Array<T>`, `Result<T, E>`) or type annotations directly in JS template literals triggers a parse error (`Unexpected token`). If context requires a code snippet, write it to a temp file and pass the path to the agent.

**Before dispatch — parallel task conflict scan (GAP E, R-10, ADR-0068 §D8):**
Read the plan at `<manifest.artifacts.plan>`. Scan each task description for explicit file-path mentions (lines containing `/` paths or filenames with extensions). The scan is binding now, in every case — merges are real (§D5), so a genuine conflict halts the run (see the Conflict halt below), not merely warns past it. If the same file path appears in multiple task descriptions, those task groups are sequenced instead: dispatched one after another, never in the same `parallel()` batch, so each group's worktree merges into the feature branch before the next group's coder forks from it. Emit before dispatching:
> "File conflict risk: `<path>` appears in tasks <N> and <M>. Sequencing these task groups instead of dispatching them in the same parallel() batch."
Groups with no path overlap keep the default parallel dispatch — sequencing is scoped to the conflicting groups only.

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
**Declare any plan constraint you do not implement (ADR-0073 §D1, issue #178).** If the plan
specifies something concrete — a validation bound, an interface shape, a named approach — and you
decide against it, do NOT implement it silently. Emit one line per case in your report, in the
terminal `PLAN DEVIATIONS:` block, before `PATTERN:`:

```
PLAN DEVIATIONS:
- task <N> | <the constraint, quoted or closely paraphrased> | declined|altered | <one line: why>
```

Emit the literal line `PLAN DEVIATIONS: none` when there are none. Deviating is legitimate and
often correct — a plan is written before the code is read. What is not legitimate is deviating
without saying so, because the human approving Gate 5 then has to find it by reading the diff.

Implement ONLY what is specified in the plan above. Do NOT implement features marked [ ] (planned but not yet started) or re-implement anything marked [x] (already done). Use the roadmap only to understand existing interfaces, naming, and patterns you must stay consistent with.
[END IF]

Build the script with pipeline(), one entry per task group, stages **tester → coder** (extended
with an optional third reviewer stage below when checkpoint review is on) — the tester runs
BEFORE the coder so it is briefed from the specification, never from the implementation
(ADR-0049 §D1: ordering makes the separation a property of the dispatch graph, not a request an
agent holding `Read` can silently ignore). Use your Pre-flight Pattern Classifier (ADR-0001) for
every Edit operation. Auto mode active. No intermediate HITL. `.claude/test-cmd` is off-limits —
never read, write, or modify it. If the test command needs changing, stop and report it to the
orchestrator.

**Stage 1 — tester.** Pin `agentType: "tester"`, `model: "sonnet"`, `effort: "xhigh"`, and
`isolation: "worktree"` explicitly on this `agent()` call — the effort table above is
documentation, not a binding, and an omitted `effort` silently inherits this session's `high`
(ADR-0018 addendum; ADR-0049 §D6 applies the same rule to this new dispatch site). `tester` has
no `isolation` in its own frontmatter (F5), and frontmatter never reaches the Workflow path
anyway (F4 as corrected by ADR-0068 F16), so an omitted value here means no worktree at all, not
an inherited default (ADR-0068 §D6, R-09). Brief the tester from the SPEC's requirement
IDs, never from implementation files (none of this group's implementation exists yet):
```bash
bash <spec-coverage.sh, resolved exactly as in the Requirement-ID coverage gate below> \
  --spec <manifest.artifacts.spec> --plan <manifest.artifacts.plan> --list
```
- Output lists one or more `R-NN` identifiers → brief the tester with that list: one failing test
  per requirement ID this task group covers.
- Else (the SPEC declares no IDs) → brief the tester from the SPEC's Success Criteria section,
  verbatim.
- Else (Success Criteria is also absent or empty) → brief the tester from this task group's plan
  task text.
The tester writes failing tests only, for this task group, and reports back which requirement
IDs (or which Success Criteria / plan-task lines, per whichever fallback fired) each test covers.

**The fallback chain above decides WHAT to assert. The plan decides WHERE and under what name, and
is read in every case — never as a fallback (ADR-0088, issue #241).** Add to the brief: work
through this task group's sub-steps and execute every one that creates or edits a test file. Those
sub-steps belong to the tester, because the coder dispatched next is denied them by
`test-write-scope.sh` — so a skipped sub-step is a sub-step nobody can do. Where a sub-step says to
confirm a failing assertion and stop, it stops: a red assertion left red is the deliverable, not an
unfinished task. The tester reports which sub-steps it executed and which it leaves to the coder.

Also add to the brief: Writes go under the dispatched worktree, never to an absolute path into the shared checkout: `isolation: worktree` bounds the working directory, not the filesystem, and an absolute path resolves out of it (ADR-0068 §D11, issue #245). Read the planning artifacts by absolute path; write by relative path.

#### Merge-back and base-fork audit (ADR-0068 §D5, §D6, §D9)

One resolution site, referenced by both dispatch paths (the Workflow stages above and below,
Step 6's fix-agent dispatch, and the Agent-tool fallback below) — stated once, the same
convention as `#### Pattern seed handoff` and `#### Proportional audit depth`. It runs after the
tester's `agent()` call above returns and before Stage 2 below creates the coder's worktree.

**The orchestrator commits, never the agent.** `coder.md`'s "never commits" instruction is
untouched by this feature; this snapshot happens only after the dispatch has already returned
(R-08). `$PRE` = `git rev-parse HEAD` on the feature branch, captured immediately before this
stage was dispatched.

`$WT` and `$WB` are obtained differently depending on dispatch path — there is no single method
that covers both:

- **Agent-tool path:** `$WT` = `worktreePath`, `$WB` = `worktreeBranch`, both read directly from
  the dispatch result alongside the agent's report (F10).
- **Workflow path:** the dispatch result carries no worktree identity at all (F19) — the run
  journal records only `agentId`, `key`, `result` and `type`, and the task notification carries no
  worktree block, though the worktree itself IS created (F16). Locate it by enumerating
  `git worktree list` and selecting the entry that is not the main working tree. Prefer
  enumeration over deriving the path from the run id: F20 records `.claude/worktrees/<runId>-<n>`
  (worktree branch `worktree-<runId>-<n>`) only as an observed naming convention, not a reported
  contract, and relying on it is exactly the class of undocumented assumption this ADR exists to
  stop. The convention may be noted as a documented fallback, but only subordinate to enumeration,
  never as the primary mechanism.

Do not collapse these back into one method: the Workflow path does not report worktree identity
(F19), so assuming F10's fields apply there leaves the coder's work orphaned on an unmerged
branch — precisely the defect this feature exists to repair, reappearing on the other dispatch
path.

<!-- fence-illustration: carries `<base-fork halt: …>` and `<conflict halt: …>` pseudo-code in place of the halt procedures, so it does not parse as bash and cannot be executed; it specifies a protocol for the orchestrator to follow, not a script to run -->
```bash
# $PRE = git rev-parse HEAD, captured on the feature branch BEFORE this stage was dispatched
# $WT / $WB — Agent-tool path: worktreePath / worktreeBranch, from the dispatch result (F10).
#             Workflow path: no identity is reported (F19) — enumerate `git worktree list` and
#             select the entry that is not the main working tree instead of deriving the path
#             from the run id (F20 is an observed convention, not a contract).
# ESCAPE CHECK (ADR-0068 §D11, issue #245) — runs BEFORE the merge, on the SHARED checkout, not
# the worktree. `isolation: worktree` bounds the agent's cwd, not its filesystem reach: an
# absolute path resolves and writes here. Untracked, not `--porcelain`: the manifest is
# legitimately modified-tracked throughout Step 5 (issue #239), so a dirty-tree check would fire
# on every stage. The chain itself creates no untracked file in Step 5 — step5-report.json is
# gitignored — so anything here came from outside the worktree it was supposed to stay in.
ESCAPED=$(git ls-files --others --exclude-standard 2>/dev/null)
[ -z "$ESCAPED" ] || <escape halt: report $ESCAPED as written outside the dispatched worktree,
                      preserve $WB, do NOT merge, stop>
[ -d "$WT" ] || { echo "nothing to merge: worktree auto-removed"; }   # F6, not an error
if [ -d "$WT" ] && [ -n "$(git -C "$WT" status --porcelain 2>/dev/null)" ]; then
  BASE_SHA=$(git -C "$WT" rev-parse HEAD)      # fork point, captured BEFORE any commit lands
  [ "$BASE_SHA" = "$PRE" ] || <base-fork halt: report both shas, preserve $WB, stop>
  git -C "$WT" add -A
  git -C "$WT" commit -m "chore(step5): snapshot <stage> worktree (<agent_type>)"
  git merge --no-edit "$WB" || {
    CONFLICTS=$(git diff --name-only --diff-filter=U)   # capture BEFORE the abort below — it clears the unmerged paths; do not reorder these two lines
    git merge --abort
    <conflict halt: report worktree branch $WB and $CONFLICTS, preserve the branch, stop>
  }
  git worktree remove "$WT" 2>/dev/null || true
fi
```

Either check in the `if` failing is **"nothing to merge"** — not an error, no forced empty
commit, and no `worktree_merges` entry (R-14). On a successful merge,
append one `worktree_merges` entry — `{stage, agent_type, branch, base_sha, merge_result}` — to
`step5-report.json`; append none when nothing was merged. The array is additive: its absence in
an older report means the run predates this feature, not that the report is malformed. After a
successful merge the worktree is pruned; an **unmerged** worktree (halted, or left over from a
conflict) is reported and preserved, never silently deleted.

**Escape halt, and why it runs before the merge rather than at commit time (ADR-0068 §D11, issue
#245).** An agent that writes through an absolute path lands in the shared checkout, and the damage
is not the file — it is the merge. `git merge` refuses to overwrite an untracked file at a path the
merge wants to create, so a stray write at exactly the path the worktree branch adds aborts the
merge and gets reported as a conflict whose named cause is wrong. Checking here names the real one.
`commit`'s Step 1 untracked list (ADR-0062) would catch the same debris several steps later, which
is too late to protect this.

Measured, not assumed (issue #245): the agent's `pwd`, `git rev-parse --show-toplevel` and the
`PreToolUse` payload's `cwd` are all the worktree, and `tool_input.file_path` arrives resolved to an
absolute path. **A `PreToolUse` hook keyed on that would still not have caught the observed
incident**, which came through `mkdir`/`cp` — Bash, whose `tool_input` carries no `file_path` at
all. That is why this check is here and not in a hook.

**Base-fork halt, and why it is a halt, not a report.** `BASE_SHA != $PRE` means the worktree
forked from somewhere other than the feature branch — the exact defect this feature exists to
fix, occurring after the Step 5 pre-flight assertion (R-05) already passed: a mid-run edit to
`settings.json`, or a future CC build changing the semantics. It halts on the same path as the
Task 7 conflict halt, naming both shas, rather than merely reporting the mismatch. The
false-positive analysis is short enough to state here: the stage protocol serialises dispatch →
merge → next dispatch, so `HEAD` cannot legitimately move between `$PRE` and the sha the worktree
reports, and the auto-removed and empty-diff cases are already handled as nothing-to-merge above
this comparison. A mismatch is therefore always the defect, never a false alarm.

**Conflict halt, and why no automatic resolution is attempted (R-12, ADR-0068 §D8).**
`git merge --no-edit "$WB"` failing means the just-committed worktree snapshot and the feature
branch touched the same lines. `$CONFLICTS` is captured with `git diff --name-only
--diff-filter=U` BEFORE `git merge --abort` runs — the abort clears the unmerged-paths state
`--diff-filter=U` reports, so capturing it afterward would yield nothing; this is exactly the kind
of ordering a later edit could "tidy" into breakage, which is why the code comment says so
directly. The halt reports the worktree branch name (`$WB`) and `$CONFLICTS`, preserves the branch
(no `git worktree remove`, no branch deletion), and stops. No automatic resolution is attempted:
no rebase, no `-X ours`, no resolver dispatch — an automatic rebase over agent-authored work can
produce a syntactically valid, semantically wrong result that no gate in this repository would
catch. Under autopilot the halt is recorded in `step5-report.json` rather than prompted to a
human, the same non-interactive behavior ADR-0050's assertions already apply elsewhere on this
path. This shares the same `if` block as the base-fork halt above; the two halts are distinguished
by their message, not duplicated as two separate checks.

**Ordering.** This merge-back completes — the tester's worktree is committed and merged into the
feature branch — before Stage 2 below creates the coder's worktree, so the coder forks from a
`HEAD` that already contains this task group's red tests (R-09). `worktree.baseRef: "head"` does
not make this step redundant: `"head"` means the commit `HEAD` points at, not the working tree,
and a worktree forks from a commit — the tester's output is uncommitted until this merge lands it
there (ADR-0068 §D6, §D9).

**Stage 2 — coder.** Pin `agentType: "coder"`, an explicit `model` (per the model-override rule
above), an explicit `effort` (per the effort table above), and `isolation: "worktree"` explicitly
(ADR-0068 §D1, §D7) — there is no second mode. Every
coder prompt at this stage MUST include, verbatim, ASCII hyphen (ADR-0049 §D3 — a paraphrase or
an em dash leaves the guard silently inert, issue #87):
```
TEST-AUTHORING SCOPE - the tester agent owns test files for this task. Do NOT create or edit tests.
Sub-steps in your tasks that create or edit test files were executed by the tester before this
dispatch and are NOT yours. Do not repeat them and do not edit those files. If that leaves a task
looking incomplete, say so in your report rather than closing the gap yourself. Make the red tests
green, except where the plan defers a red assertion to a later task: an assertion the plan defers
to a later task stays red, and your report says which one and why.
Writes go under the dispatched worktree, never to an absolute path into the shared checkout: `isolation: worktree` bounds the working directory, not the filesystem, and an absolute path resolves out of it (ADR-0068 §D11, issue #245). Read the planning artifacts by absolute path; write by relative path.
```
A coder whose write is denied by `test-write-scope.sh` is reading a consistent story: the tester
agent owns test files for this task, and the correct response is to report the gap to the
orchestrator, not to retry the write.

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
| `architect`, `coder`, `tester` | `xhigh` |
| `reviewer`, `debugger` | `high` |
| `refactorer` | `medium` |
| `doc-writer`, `researcher` | `low` |

If an agent's frontmatter changes, this table is the second place to update — they are not
linked, and a mismatch here silently overrides the file.

[IF manifest.step5_review_mode = checkpoint — add this block to dispatch, otherwise omit entirely:]
Checkpoint review: ON (ADR-0039 D5-D9).
Extend the tester → coder pipeline() above with a third stage: reviewer.
Do NOT use parallel() as a barrier between the stages — task B must keep implementing while
task A is under review. Wall-clock is the slowest single-task chain, not sum-of-slowest-per-stage.
Stage 3 dispatches agentType "reviewer" scoped to the files Stage 2 (coder) reported for that task.
Pass an explicit model AND an explicit effort of "high" (same rules as the coder above).
It REVIEWS ONLY and fixes nothing.
Pass each task's BLOCKER and MAJOR findings into the prompt of the next task's Stage 2 (coder) as
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
4. Run the `Anti-test-weakening gate — Step 5 → Step 6 (ADR-0047)` block once, before
   deciding the transition.
5. Run the `Requirement-ID coverage gate — Step 5 → Step 6 (ADR-0048)` block once, before
   deciding the transition.
6. Run the `Diff budget and scope check — Step 5 checkpoints (ADR-0052)` block once, over the
   cumulative diff and every completed task — it never affects the transition (advisory only).
7. Run the `Task-level metrics — Step 5 checkpoints (ADR-0064, issue #118)` block once, over the
   same cumulative diff and every completed task — it never affects the transition and is not
   surfaced at Gate 5 (metrics, not findings, ADR-0064 §D2).
8. If all tasks passed, `test_result` is `green` or `n/a`, the weakening gate found no
   `WEAKENED` line, and the coverage gate exit code is `0` → transition to `step_6_review`.
   Present Gate 5.

Set `step5_mode: "workflow"` in the manifest (via bash sed substitution on the additive
field — NOT via Edit tool).

#### Generator/verifier separation — tester stage and coder test-write deny (ADR-0049)

Both dispatch paths in this Step (the Workflow pipeline() above and the Agent-tool batch
fallback below) stage a `tester` agent BEFORE the `coder` agent, per task group (ADR-0049 §D1).
The tester writes the failing tests from the SPEC's requirement IDs (`spec-coverage.sh --list`,
falling back to the Success Criteria section and then to plan task text — never from
implementation files, since none exists yet at this point of the pipeline). Ordering, not an
instruction to the coder, is what makes the separation real: a tester briefed after the coder
could Read the implementation at no cost and with no trace, and only ordering removes that.

Enforcement is `test-write-scope.sh`, a `PreToolUse` hook on `Edit|Write|MultiEdit` (registered
by Task 8 of ADR-0049's plan — inert until an operator wires it into `settings.json`). It denies
the **coder** agent any create or edit of a test-file-shaped path, but only when the coder's own
dispatch prompt carries this marker verbatim, ASCII hyphen (never an em dash — issue #87 made a
typographic substitution silently inert once already):
```
TEST-AUTHORING SCOPE - the tester agent owns test files for this task. Do NOT create or edit tests.
```
Both dispatch templates below emit it on every coder prompt. A coder whose write is denied is
reading the same recovery path stated in Stage 2 above: the tester agent owns test files for this
task — report the gap to the orchestrator instead of retrying the write.

This is a guardrail against a shortcut, not a sandbox (ADR-0041/ADR-0045's distinction, applied
again here): a coder that writes a test via `Bash` heredoc, or writes test-shaped content to a
non-test-shaped path, is invisible to this hook. Keying the deny on `agent_type == "coder"` alone
was rejected (ADR-0049 §D3) — RTF Phase 3, `deep-refactor` and this same skill's Step 6 all
dispatch fix agents with `agentType: "coder"` to legitimately repair a broken test, and the
marker, not the agent type, is what distinguishes a Step 5 implementation coder from those.

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
  "weakening_findings": [
    { "file": "tests/test_billing.py", "reason": "deleted-test-file" }
  ],
  "suspect_findings": [
    { "file": "tests/test_billing.py", "detector": "zero-assertion-test", "line": 42 }
  ],
  "weakening_scan": "ran | unavailable",
  "requirement_coverage": {
    "ids_declared": 6,
    "uncovered": [ { "id": "R-02", "missing": "plan" } ],
    "status": "pass | fail | no-ids | unavailable"
  },
  "tests_written_by": [
    { "task": 1, "agent": "tester" }
  ],
  "budget_findings": [
    { "task": "3", "files_expected": 1, "files_actual": 2,
      "lines_expected": 120, "lines_actual": 210, "out_of_scope": ["src/unrelated.py"] }
  ],
  "plan_deviations": [
    { "task": "2", "constraint": "<the plan constraint, quoted or closely paraphrased>",
      "action": "declined | altered", "reason": "<one line: why>" }
  ],
  "task_metrics": [
    { "task": "3", "test_count_delta": 2, "deleted_lines": 14,
      "iteration_count": 2, "elapsed_wall_seconds": 187 }
  ],
  "accessibility_i18n_findings": [
    { "item": "labels", "status": "pass | fail | not-applicable", "note": "<one line>" },
    { "item": "contrast", "status": "pass | fail | not-applicable", "note": "<one line>" },
    { "item": "dynamic-type-or-scaling", "status": "pass | fail | not-applicable", "note": "<one line>" },
    { "item": "keyboard-or-assistive-tech-reachability", "status": "pass | fail | not-applicable", "note": "<one line>" },
    { "item": "i18n-unicode-multibyte", "status": "pass | fail | not-applicable", "note": "<one line>" },
    { "item": "i18n-no-english-centric-examples", "status": "pass | fail | not-applicable", "note": "<one line>" },
    { "item": "i18n-no-locale-formatting-assumed", "status": "pass | fail | not-applicable", "note": "<one line>" }
  ],
  "errors": []
}
```

**`task_metrics` is a METRICS array, not a findings array (ADR-0064 §D2) — it is documented here,
in its own paragraph, deliberately outside the "six advisory arrays" roll-up described in the Gate
5 block below.** A finding asserts something is wrong and asks for a decision; a metric is a
number with no claim attached. `task_metrics` carries the four ADR-0064 D1 instrumentation
metrics — test-count delta, deleted lines, iteration count, elapsed wall time — computed once per
Step 5 checkpoint (the same cadence as `budget_findings` immediately above: once after the
Workflow path completes, once per batch checkpoint in the Agent-tool fallback), tagged with the
same `task` checkpoint label. It is **not surfaced at Gate 5, not counted in the advisory roll-up,
and not presented as actionable** — see the "Task-level metrics" block after the Diff budget and
scope check below for how each field is computed, and the Gate 5 block for the explicit exclusion.
Every field within an entry is independently **conditional-if-present**: a field absent from an
entry means that one metric was not measured for that checkpoint, and MUST NOT be read as `0`
(ADR-0064 §D3 — the same rule ADR-0046's exit codes and ADR-0043's completeness check already
apply elsewhere in this codebase, here applied to stored data). A `0` in a present field is a real,
computed zero (e.g. a checkpoint that genuinely deleted no lines). The `task_metrics` array itself
is absent, as a whole, on any manifest predating this feature — that is not malformed either.

**`accessibility_i18n_findings` IS a findings array, unlike `task_metrics` immediately above —
same distinguishing test ADR-0064 §D2 draws for `task_metrics`, opposite answer: a metric is a
number with no claim attached, and `"labels": "fail"` is a claim about the work (ADR-0066 §D2).**
It is written by **Gate 5.05**, not Step 5, so it is a *seventh* advisory-schema finding array in
this same schema — see the Gate 5 roll-up block below for why it is not folded into that block's
six-array count, and the Gate 5.05 block for where it renders instead. Each entry carries one of
the seven named checklist items (four accessibility, three i18n — ADR-0066 §D1/§D3) with a
`pass | fail | not-applicable` status and a one-line note. **It is never a failure signal**
(ADR-0066 §D2 — the gate records an answer, it does not block, a deliberate and disclosed
divergence from the SPEC's "gate, not aspiration" wording). The array is absent, as a whole, on
any chain that touched no UI-shaped file this cycle — the same condition Gate 5.05 already applies
to `ui-layout-audit` (ADR-0066 §D4), not a second one, and absence here is **not malformed**, it
is what a CLI-only or docs-only chain produces.

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
- `weakening_findings` non-empty → **failure signal**, same handling as `tasks_failed`; absent means none and is **not** malformed.
- `suspect_findings` is **never a failure signal** and never blocks the transition to
  `step_6_review`, in attended mode or under autopilot (ADR-0051 §D2). Each entry is a heuristic
  over a diff with no type information and no test execution — the same distinction
  `weakening-scan.sh` itself draws between its `WEAKENED` and `SUSPECT` sentinels (never
  `grep -q '^WEAKENED'` on a `SUSPECT` line, and never the reverse). Absent means none and is
  **not** malformed. It is advisory only: presented at Gate 5 with its per-detector breakdown so
  a human sees it, never acted on automatically (ADR-0051 §D3).
- `requirement_coverage.uncovered` non-empty → **failure signal**, same handling as
  `tasks_failed`; `requirement_coverage` absent means the gate did not write one and is
  **not malformed** — the malformed check stays `step5_mode` + `tasks_completed`, unchanged.
- `tests_written_by` is **never** a failure signal (ADR-0049 §D5). It is self-reported by the
  agents whose separation it describes — the same class of claim ADR-0047 §A3 and ADR-0048 §A7
  already refuse to trust for their own arrays, and this array carries no better authority.
  Absent is **not** malformed — it is what a run before this feature, or a run where
  `test_cmd_placeholder`/`test_cmd_provisional` skipped the tester stage, produces. A `"coder"`
  entry (an implementation coder wrote a test — either `test-write-scope.sh` denied nothing, or
  it was never wired) is surfaced at Gate 5 for a human to read; it is a record, never a gate.
- `plan_deviations` is a **DISCLOSURE, not a gate** (ADR-0073 §D1, issue #178), and never a failure
  signal in any mode. It records a plan constraint the coder chose not to implement, so the choice
  reaches Gate 5 as a list to approve rather than as something the orchestrator must notice while
  reading a diff. Absent means none was declared and is **not** malformed.
  **It is a self-report, and that is fine here precisely because it is not a gate.** This system's
  own rule — do not trust an agent's self-report as the gate (ADR-0047 §A3, RTF Step 3) — is about
  gates. A disclosure feeding a human decision is the opposite case: a coder that hides a deviation
  leaves the reviewer exactly where it was before this field existed, so the field can only add
  information, never remove a check. Nothing verifies it, and nothing should be built on it as if
  something did.
- `budget_findings` is advisory only and **never a failure signal** (ADR-0052 §D3). A per-task line-count ceiling is
  an estimate made before the work by an agent that has not read every file it will touch — it
  will be wrong regularly and in both directions, so a gate on it would halt on noise more often
  than on signal (the same reasoning `suspect_findings` already established for a heuristic
  finding at this same boundary). Absent means either the checker did not resolve or the plan
  declares no budgets on the relevant tasks (ADR-0052 §D1) — either way, **not malformed**.
- `task_metrics` is **never** a failure signal and is **not one of the advisory arrays** —
  it is a METRICS array (ADR-0064 §D2): no claim is attached to a number, so there is nothing
  here to gate on. Absent (the whole array, or any single field within an entry) means that
  metric was not measured for that checkpoint. Never read an absent field as `0` (ADR-0064 §D3):
  a present field's `0` is a real, computed zero; an absent field is not recorded at all, and a
  reader collapsing the two would quietly manufacture a well-behaved-looking task out of one that
  was never measured. Every value computed here comes
  from `git` or from the orchestrator's own dispatch bookkeeping, never from an agent's report
  (ADR-0064 §D4) — see the "Task-level metrics" block below for the exact computation of each of
  the four fields.
- `accessibility_i18n_findings` is **never** a failure signal (ADR-0066 §D2): the gate records an
  answer, it does not block, a deliberate divergence from the SPEC's "gate, not aspiration"
  wording — disclosed here rather than resolved in either direction. It IS one of the
  advisory-schema finding arrays (unlike `task_metrics` immediately above — each entry is a claim,
  `"contrast": "fail"`, not a bare number), it is just written by Gate 5.05 rather than Step 5, so
  it is not part of the six-array Gate 5 roll-up computed before Gate 5.05 has run — see that
  block for the reason. Absent means either no UI-shaped file was touched this cycle (ADR-0066
  §D4, the inherited Gate 5.05 condition) or the array predates this feature — either way, **not
  malformed**.
- Contrast, six arrays in one schema with different gate semantics: `checkpoint_reviews`,
  `tests_written_by`, `suspect_findings`, `budget_findings` and `accessibility_i18n_findings` are
  never a failure signal; `weakening_findings` always is (ADR-0047 §D5, ADR-0049 §D5, ADR-0051
  §D2, ADR-0052 §D3, ADR-0066 §D2). `task_metrics` sits outside this contrast entirely — it is not
  a finding of any kind.

#### Anti-test-weakening gate — Step 5 → Step 6 (ADR-0047)

The orchestrator runs this scan itself — do not trust the agent's self-report for this gate.
This is the same rule `review-triage-fix` Step 3 already applies to CIRCUIT BREAKER B: the
agent whose work is being examined for test weakening is not the one who gets to report on it.

**Resolution:**
```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] \
   && [ -f "$CLAUDE_PLUGIN_ROOT/skills/review-triage-fix/scripts/weakening-scan.sh" ]; then
  _wscan="$CLAUDE_PLUGIN_ROOT/skills/review-triage-fix/scripts/weakening-scan.sh"
elif [ -f "$HOME/.claude/skills/review-triage-fix/scripts/weakening-scan.sh" ]; then
  _wscan="$HOME/.claude/skills/review-triage-fix/scripts/weakening-scan.sh"
else
  _wscan=""     # scan did not run — report it, do not infer a clean result
fi
```

**Scan and blocking idiom.** The script always exits 0 and prints the sentinel `CLEAN` when it
finds nothing over the cumulative diff since the pre-dispatch mark, so the caller branches on
stdout content, never on exit code and never on emptiness:
```bash
if [ -n "$_wscan" ]; then
  _wk=$(git diff "$_pre5" 2>/dev/null | bash "$_wscan" 2>/dev/null)
  if printf '%s\n' "$_wk" | grep -q '^WEAKENED'; then
    # blocking path — see policy below
  fi
fi
```
- `grep -q '^WEAKENED'`, anchored. Never `[ -n "$_wk" ]` — the script prints `CLEAN` when it
  finds nothing, so the output is never empty and an emptiness test is always true:
  **never gate on empty output**.
- **`CLEAN` means "no detector fired", never "no weakening occurred" (ADR-0073 §D4, issue #177).**
  The blind spot with a name: an assertion edited IN PLACE removes one assert-bearing line and adds
  one, so `assert-removed`'s count comparison cannot fire. Flipping `is True` to `is False` to match
  what the implementation produces is invisible to every detector in that script. No detector was
  added — the diff shape is ambiguous by construction and the measurement showed 0-of-2 precision on
  this repository's own history (see the script's header). **When this gate reports CLEAN, the
  assertions in the diff have not been checked by anything.** Reading the test diff at the commit
  gate is what covers it, and that is a human step, not a mechanical one.
- Never `n=$(… | grep -c '^WEAKENED' || echo 0)` — `grep -c` prints `0` **and** exits 1 on no
  match, so `|| echo 0` appends a second line and `n` becomes the two-line string `0\n0`.

**SUSPECT findings (ADR-0051, issue #105) — advisory, non-blocking, extracted from the same
`$_wk` output.** `weakening-scan.sh` also emits a separate `SUSPECT<TAB><file><TAB><detector><TAB><line>`
sentinel for four heuristic reward-hacking detectors (`literal-assertion-added` — ships disabled
by default, see the script header — `zero-assertion-test`, `deleted-public-symbol`,
`swallowed-error`). `SUSPECT` never matches `^WEAKENED` and this gate must never grep for it as a
blocking condition — that promotion is exactly what ADR-0051 §D2 rejects:
```bash
if [ -n "$_wscan" ]; then
  _sus=$(printf '%s\n' "$_wk" | grep '^SUSPECT' || true)
fi
```
Record every `SUSPECT` line as a `{file, detector, line}` entry in `step5-report.json`'s
`suspect_findings` array (empty array if `_sus` is empty). Present the count and a per-detector
breakdown at Gate 5 (see the Gate 5 block in `## 5. HITL gates`) so a human reviewing the cycle
sees it — the finding is surfaced, never acted on automatically (ADR-0051 §D3).

**Policy:**
- Attended: present the `WEAKENED` findings and do NOT transition to `step_6_review` without user
  acknowledgment. `SUSPECT` findings are informational only — they never block this transition,
  they are simply carried forward into `suspect_findings` and shown at Gate 5.
- Autopilot (`manifest.autopilot = true`): halt on `WEAKENED` — do not transition, do not proceed
  to Gate 5. `SUSPECT` findings never halt autopilot either; they still populate
  `suspect_findings` for the eventual Gate 5 (or the autopilot report) to surface.
- `_wscan` empty (script did not resolve): record `"weakening_scan": "unavailable"` in
  `step5-report.json` and proceed — fail-open, visibly, per ADR-0047 §D2. `suspect_findings` is
  correspondingly absent (not malformed — the gate did not run).

#### Requirement-ID coverage gate — Step 5 → Step 6 (ADR-0048)

Checks that every requirement ID the SPEC declares is cited by a plan task and mentioned by a
test — the drift ADR-0048 exists to catch, invisible to every gate that only measures whether
the plan itself was executed.

**Resolution** (skill-helper path shape, `skills/concept-to-code/scripts/`, **not** `hooks/` —
`~/.claude` has two script locations and a resolution block copied from #100's reporters
resolves nothing here):
```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] \
   && [ -f "$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/spec-coverage.sh" ]; then
  _scov="$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/spec-coverage.sh"
elif [ -f "$HOME/.claude/skills/concept-to-code/scripts/spec-coverage.sh" ]; then
  _scov="$HOME/.claude/skills/concept-to-code/scripts/spec-coverage.sh"
else
  _scov=""     # gate did not run — report it, do not infer a clean result
fi
```

**Inputs:** `--spec <manifest.artifacts.spec>`, `--plan <manifest.artifacts.plan>`, and
`--tests-root <project_root>` — the project root, not a `tests/` guess, since discovery is by
basename. `--tests-root` is **omitted** when `manifest.test_cmd_placeholder = true` or
`manifest.test_cmd_provisional = true`: a project that has declared it has no test command, or
whose tests are still intent, cannot be held to test coverage (ADR-0018's "no test-cmd =
report-only mode", reused rather than reinvented).

**Invocation and exit-code idiom:**
```bash
# ADR-0133 §D1 (issue #394): the body between the two FENCE_BASH lines runs under BASH, not under
# the host shell, which is zsh here and differs from bash on word splitting, unmatched globs and
# `echo` escapes. That difference is load-bearing here — see the note on `${_troot:+…}` below.
# `export` forwards `_scov`, bound by the resolution block above; a plain shell variable does not
# survive the new process boundary. Terminator at COLUMN 0; an indented one is swallowed into the
# here-document and destroys this fence's exit code silently.
# NO `fence-contract` marker, deliberately (ADR-0133 §D3): this fence enters the wrapper population
# through the divergence SCANNER, not through a declaration. It cannot halt a run, so `F3` does not
# ask it for a marker, and adding one would create an `F4` execution obligation this feature did not
# budget. The absence is a decision, not an oversight. (This note deliberately avoids the standalone
# word for halting: `fence_is_abort_capable` matches it as a whole word, so a comment SAYING this
# fence cannot halt would classify it as one that can — rule 12, in the sentence written to explain
# the missing marker.)
export _scov
bash <<'FENCE_BASH'
if [ -n "$_scov" ]; then
  _troot=""
  if [ "<manifest.test_cmd_placeholder>" != "true" ] && [ "<manifest.test_cmd_provisional>" != "true" ]; then
    _troot="<project_root>"
  fi
  # `${_troot:+--tests-root "$_troot"}` expands to TWO words, and that is guaranteed by the wrapper
  # above (issue #394, ADR-0133): bash word-splits the expansion, zsh does not. Measured on a live
  # fixture under both shells: wrapped, this returns the real verdict identically under zsh and bash;
  # unwrapped under zsh the option arrived as the SINGLE argument `--tests-root <path>`,
  # `spec-coverage.sh` reported `unknown argument` and exited 2 — and `_rc = 2` is this gate's
  # fail-open branch, so ADR-0048's merge-blocking requirement-coverage gate was not merely fed an
  # unreadable token, it was passing every time a tests-root was supplied. Do not "fix" this by
  # quoting the expansion: the point of the `:+` form is that it expands to NOTHING when `_troot` is
  # empty, and quoting would pass one empty argument in its place.
  _out=$(bash "$_scov" --spec "<manifest.artifacts.spec>" --plan "<manifest.artifacts.plan>" ${_troot:+--tests-root "$_troot"} 2>&1)
  _rc=$?
  # ADR-0133 §D4: this body runs in a SUBPROCESS, so `_troot`, `_out` and `_rc` die at the
  # terminator below — and the self-repair retry block further down reads all three. They are
  # printed values now: the `SPEC-COVERAGE:` line is authoritative, and the orchestrator carries
  # `rc` and `troot` forward exactly as it carries `<manifest.artifacts.plan>` into this block.
  # `_out` is everything printed after that line. Before the wrapper the two blocks received these
  # values from each other only because they happened to share a shell — an implicit inter-block
  # dependency nothing documented.
  printf 'SPEC-COVERAGE: rc=%s troot=%s\n' "$_rc" "$_troot"
  printf '%s\n' "$_out"
fi
FENCE_BASH
```
**What this block hands on (ADR-0133 §D4).** The wrapper runs the body in a subprocess, so `_troot`,
`_out` and `_rc` do not survive the terminator. The `SPEC-COVERAGE:` line is authoritative: carry
`rc` and `troot` from it, and read `_out` as everything printed after it. The self-repair block below
declares the same three plus `_scov` as orchestrator-bound for that reason — before the wrapper they
reached it only because the two blocks happened to share a shell, an inter-block dependency nothing
documented. No `SPEC-COVERAGE:` line at all means `_scov` was empty and the gate did not run, which
is the fail-open case already described below, not a clean result.

`_rc = 0` → every declared ID covered, or the SPEC declares no IDs. `_rc = 1` → at least one ID
uncovered, `_out` names the ID and the missing half (`plan`, `tests`, or `plan,tests`). `_rc = 3`
→ structural error in the SPEC or plan (`DUPLICATE`/`MALFORMED`/`ORPHAN` in `_out`) — the remedy
is fixing the artifact, not writing a task. `_rc = 2`, or `_scov` empty → treat as unavailable,
fail-open (see Policy).

**Self-repair on the one structural error that has a mechanical fix (ADR-0072 §D3, issue #171).**
Before treating `_rc = 3` as a stop, check whether the cause is the plain-bullet form — requirement
ids declared as `- R-01 — …` instead of `- [ ] R-01 — …`. It is the only structural error whose
repair is deterministic: the two lines say the same thing and only the second is one the checker
reads, so adding the marker changes no content.

```bash
# ADR-0133 §D1 (issue #394): the body between the two FENCE_BASH lines runs under BASH, not under
# the host shell, which is zsh here and differs from bash on word splitting, unmatched globs and
# `echo` escapes — see the `${_troot:+…}` note in the invocation block above, which applies verbatim
# to the re-run below. Terminator at COLUMN 0; an indented one is swallowed into the here-document
# and destroys this fence's exit code silently.
# Free variables, bound by the orchestrator from the invocation block's `SPEC-COVERAGE:` line and
# from the resolution block above it: `_rc`, `_out`, `_troot`, `_scov` (ADR-0133 §D4). That block
# runs in its own subprocess, so these do NOT arrive through a shared shell; the orchestrator
# carries them, exactly as it carries `<manifest.artifacts.spec>`.
# NO `fence-contract` marker, deliberately (ADR-0133 §D3): scanner-derived population member, and it
# cannot halt a run, so no `F3` obligation and no `F4` execution obligation is created here. The
# standalone word for halting is avoided on purpose — `fence_is_abort_capable` matches it as a whole
# word, so writing it here would classify this fence as one that can halt (rule 12).
export _rc _out _troot _scov
bash <<'FENCE_BASH'
if [ "$_rc" -eq 3 ] && printf '%s\n' "$_out" | grep -q 'declared as plain bullets'; then
  _norm="$(dirname "$_scov")/spec-normalize-ids.sh"
  if [ -f "$_norm" ]; then
    _diff=$(bash "$_norm" --spec "<manifest.artifacts.spec>" --apply); _nrc=$?
    # §D4: `_diff` dies at the terminator too, so the block emits it under the heading the
    # paragraph below mandates, rather than leaving the orchestrator to read a variable that no
    # longer exists. It goes FIRST so the ordering contract stays simple: the repair diff, then the
    # re-run verdict, and everything after the `SPEC-COVERAGE:` line is `_out`.
    printf 'Requirement ids: repaired plain-bullet declaration(s) — diff:\n'
    printf '%s\n' "$_diff"
    if [ "$_nrc" -eq 0 ]; then
      _out=$(bash "$_scov" --spec "<manifest.artifacts.spec>" --plan "<manifest.artifacts.plan>" ${_troot:+--tests-root "$_troot"} 2>&1)
      _rc=$?
      # The re-run's verdict must leave this subprocess the same way the first one did, or the gate
      # below reads the PRE-repair `_rc` and stops on an error that has already been fixed.
      printf 'SPEC-COVERAGE: rc=%s troot=%s\n' "$_rc" "$_troot"
      printf '%s\n' "$_out"
    fi
  fi
fi
FENCE_BASH
```

**Apply first, show after — do not gate this.** The edit is mechanical, and ADR-0071's Gate 4.0 has
already committed the planning artifacts, so `git checkout -- <spec>` reverses it. Stopping a chain
to ask permission for a checkbox marker is friction with one sensible answer, and on the unattended
paths it would be a halt with no one to answer. The block emits the diff `spec-normalize-ids.sh`
returned under the heading `"Requirement ids: repaired plain-bullet declaration(s) — diff:"` — it
prints the heading itself rather than binding a `_diff` variable, because under the ADR-0133 wrapper
that variable dies at the terminator. Surface both lines to the user, so the edit is visible after
the fact rather than invisible.

If this block prints a second `SPEC-COVERAGE:` line, it supersedes the first: it carries the
**post-repair** `rc`, and `_out` is again everything after it. If it prints none, nothing was
repaired and the first verdict stands. If the re-run still returns 3, stop as before: the cause was
something else, or something the repair does not cover. **A bold-wrapped id (`- **R-01** — …`) is no longer one of those (ADR-0122, issue
#291).** In a checklist item it reads as declared directly, no repair needed. As a plain bullet it
is a near-miss like any other and is repaired by this same automatic path, with the emphasis
preserved — `- **R-01** — …` becomes `- [ ] **R-01** — …`, never stripped. Never loop: the repair
runs at most once per gate invocation.

**This gate branches on the exit code. The anti-test-weakening gate immediately above must
never do that — `weakening-scan.sh` always exits 0 and signals through stdout. Two adjacent
gates, two idioms, on purpose: `spec-coverage.sh` is a checker with an exit-code contract,
`weakening-scan.sh` is a reporter that never decides policy.**

**Do not copy one block's branching into the other.**

**Cadence:** this gate runs once at the Step 5 exit, not at every batch checkpoint, unlike the
anti-test-weakening gate above. Mid-run, an uncovered ID is the expected state — a task that has
not executed yet legitimately leaves the ID it satisfies uncovered, and running this gate per
batch would fail on every multi-batch chain.

**Policy:**
- Attended: present the uncovered IDs (`_rc = 1`) or the structural error (`_rc = 3`) and do NOT
  transition to `step_6_review` without user acknowledgment.
- Autopilot (`manifest.autopilot = true`): halt — do not transition, do not proceed to Gate 5.
- `_rc = 2`, or `_scov` empty (script did not resolve): fail-open, visibly. Record
  `"status": "unavailable"` in `step5-report.json` and proceed.

#### Diff budget and scope check — Step 5 checkpoints (ADR-0052)

Compares what a coder's diff actually touched against what the plan said it would, at the same
checkpoints the anti-test-weakening gate above already visits (§D2 — no new checkpoint
mechanism). Purely advisory, and inert unless the architect declared a budget: a per-task line
ceiling is an estimate made before the work by an agent that has not read every file it will
touch, so it surfaces and never blocks (§D3).

**Resolution** (skill-helper path shape, `skills/concept-to-code/scripts/`, the same two-location
trap `spec-coverage.sh` above avoids):
```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] \
   && [ -f "$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/diff-budget-check.sh" ]; then
  _dbudget="$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/diff-budget-check.sh"
elif [ -f "$HOME/.claude/skills/concept-to-code/scripts/diff-budget-check.sh" ]; then
  _dbudget="$HOME/.claude/skills/concept-to-code/scripts/diff-budget-check.sh"
else
  _dbudget=""     # check did not run — report it, do not infer a clean result
fi
```

**Invocation and caller idiom.** `diff-budget-check.sh` is a REPORTER, exactly like
`weakening-scan.sh` above and unlike `spec-coverage.sh` immediately above this block: it always
exits 0 and signals through stdout, printing the sentinel `CLEAN` when there is nothing to
report. **Do not copy `spec-coverage.sh`'s branch-on-exit-code idiom into this block** — that
sentence has now been written three times in this directory (ADR-0048 §D7, the anti-test-
weakening gate above, and here).
```bash
if [ -n "$_dbudget" ]; then
  # --stat=999, never a bare --stat — git elides long paths at 80 columns (ADR-0070 §D5).
  _db=$(git diff --stat=999 "$_pre5" 2>/dev/null \
        | bash "$_dbudget" --plan "<manifest.artifacts.plan>" --tasks "<comma list of every task number dispatched so far>")
fi
```
- Never `[ -n "$_db" ]` to decide whether something was found — `$_db` is the literal string
  `CLEAN` on a clean run, never empty.
- Never `n=$(printf '%s\n' "$_db" | grep -c '^BUDGET' || echo 0)` — `grep -c` prints `0` **and**
  exits 1 on no match, so `|| echo 0` appends a second line and `n` becomes the two-line string
  `0\n0`. Use `grep -c '^BUDGET' || true` if a count is needed.
- **A third token exists: `MALFORMED<TAB>task <N><TAB><declaration text>` (issue #246).** It means
  the checker found a recognisable budget declaration it could **not read** — not that the task
  overspent, and not that it declared nothing. Surface it to the human at Gate 5 with the task
  number and the offending text, and say plainly that this task's budget was **not measured**. A
  token the caller drops is a producer with no consumer, which is the defect class #238 records;
  do not leave it unread just because it is advisory.

**Cadence, matching the anti-test-weakening gate above (§D2 — no new checkpoint mechanism, reusing
the same one).** The Workflow dispatch path runs this once, after the whole workflow completes,
over the cumulative diff since `$_pre5` and every task in `tasks_completed` from
`step5-report.json` — for the same reason the weakening gate above runs once there rather than per
pipeline stage: the orchestrator only regains control after the workflow exits. The Agent-tool
fallback runs it at every batch checkpoint (see step 4 there), `--tasks` accumulating every task
dispatched so far, against the same cumulative diff the weakening gate already re-scans at that
point.

**Record every `MALFORMED` line as its own entry in the same array**, `{task, malformed}` — the
declaration text verbatim, no `files_*` or `lines_*` keys, because nothing was measured and writing
zeros there would read as a task that spent nothing. Additive, no schema bump, the same terms as
every prior extension of this file.

**Record every `BUDGET` line's `files=<exp>/<act>` and `lines=<exp>/<act>`, and every `SCOPE`
line's file, as one entry per checkpoint call** in `step5-report.json`'s `budget_findings` array
(`{task, files_expected, files_actual, lines_expected, lines_actual, out_of_scope}` — `out_of_scope`
collects that call's `SCOPE` file names; the plan-level scope check has no single owning task to
attribute a `SCOPE` finding to, so it rides on the same checkpoint entry). Empty array if `$_db`
is `CLEAN`.

**Policy:**
- `budget_findings` is **never a failure signal**, attended or under autopilot (ADR-0052 §D3) —
  it never blocks the transition to `step_6_review`. Findings are carried into `budget_findings`
  and folded into the Gate 5 roll-up (ADR-0052 §D5, see the Gate 5 block in `## 5. HITL gates`).
- `_dbudget` empty (script did not resolve): record no `budget_findings` entries for that
  checkpoint and proceed — fail-open, visibly, matching the weakening gate's own
  `"weakening_scan": "unavailable"` idiom.

#### Task-level metrics — Step 5 checkpoints (ADR-0064, issue #118)

**These are METRICS, not findings (ADR-0064 §D2).** A finding asserts something is wrong and asks
for a decision; a metric is a number with no claim attached. This block is not surfaced at Gate 5,
is not counted in the advisory roll-up below, and is not presented as actionable — it feeds
`task_metrics` in `step5-report.json` only, for the analysis rut detection and trust scoring will
eventually need (ADR-0064 §A5: no such detector or threshold exists yet, and building one against
an empty corpus would mean inventing a threshold rather than measuring one — this feature builds
the inputs only). Runs at the same checkpoints as the two blocks immediately above (§D2 of both
ADR-0047 and ADR-0052 — no third checkpoint mechanism): once after the Workflow path completes,
once per batch checkpoint in the Agent-tool fallback below.

**Every field is computed, never self-reported (ADR-0064 §D4).** None of the four fields is
requested in any tester or coder dispatch prompt in this Step, and no dispatch template below asks
an agent to report an iteration count, an elapsed time, a test count, or a line count — each of
the four is produced independently by the orchestrator from `git` output or from its own dispatch
bookkeeping.

**Resolution** (skill-helper path shape, `skills/concept-to-code/scripts/`, the same two-location
pattern `spec-coverage.sh` and `diff-budget-check.sh` above use):
```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] \
   && [ -f "$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/agent-metrics.sh" ]; then
  _ametrics="$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/agent-metrics.sh"
elif [ -f "$HOME/.claude/skills/concept-to-code/scripts/agent-metrics.sh" ]; then
  _ametrics="$HOME/.claude/skills/concept-to-code/scripts/agent-metrics.sh"
else
  _ametrics=""     # did not resolve — OMIT test_count_delta and deleted_lines from this
                    # checkpoint's entry, do NOT invoke the script and default its output to 0
fi
```

**`test_count_delta` and `deleted_lines` — from `git`, via `agent-metrics.sh`.** The script reads
the SAME full unified diff already piped into the anti-test-weakening gate above (`git diff
"$_pre5"`, not a second git call, not `--stat`/`--numstat`) and always prints two TAB-separated
lines, `DELETED_LINES` and `TEST_COUNT_DELTA`:
```bash
if [ -n "$_ametrics" ]; then
  _am=$(git diff "$_pre5" 2>/dev/null | bash "$_ametrics" 2>/dev/null)
  # The trailing `[[:space:]][[:space:]]*` requires at least one separator, so a longer token
  # (`DELETED_LINES_X`) cannot satisfy the shorter one's pattern. A negative TEST_COUNT_DELTA
  # survives: the substitution removes only the token and the separator run.
  _dl=$(printf '%s\n' "$_am" | sed -n 's/^DELETED_LINES[[:space:]][[:space:]]*//p')
  _tcd=$(printf '%s\n' "$_am" | sed -n 's/^TEST_COUNT_DELTA[[:space:]][[:space:]]*//p')
fi
```
If `_ametrics` is empty, or `_dl`/`_tcd` fail to parse as an integer, OMIT that field from this
checkpoint's `task_metrics` entry — never write `0` in its place (ADR-0064 §D3). A genuinely
empty diff (nothing changed since `$_pre5`) is a real, computed zero and IS written as `0` — the
distinction is between "the script ran and measured zero" and "the script did not run", not
between "zero" and "nonzero".

`agent-metrics.sh`'s test-file predicate is reused verbatim from `test-write-scope.sh` (ADR-0049
§D4 — the "broad union minus `.md`" DENIAL predicate), not `spec-coverage.sh`'s narrower DISCOVERY
predicate in the same directory, even though both already exist and could be reused. ADR-0049 §D4
records that the two diverge on purpose: a discovery predicate must not over-match (a false
coverage pass), a denial predicate must not under-match (a missed test path is invisible).
Counting tests shares the denial predicate's failure direction — a test file this predicate
silently missed would make a real test-count drop invisible in this metric, which is exactly the
kind of quietly-manufactured well-behaved-looking task ADR-0064 §D3 already warns against, just
reached through under-matching instead of zero-defaulting. The narrower discovery predicate was
rejected for that reason, not reused.

**`iteration_count` and `elapsed_wall_seconds` — from the dispatch loop, no script.** Before the
first dispatch in this Step, alongside `_pre5=$(git rev-parse HEAD)`, also record
`_pre5_ts=$(date -u +%s)`. At each checkpoint:
- `elapsed_wall_seconds` = `$(date -u +%s)` at the checkpoint minus `$_pre5_ts` — cumulative since
  Step 5 began, the same cumulative-since-`$_pre5` convention `budget_findings` and the weakening
  gate already use. This measures wall-clock time, not agent effort — it includes queueing, rate
  limiting, and anything else in the way (ADR-0064 negative consequence, stated here rather than
  only in the ADR: do not read this figure as effort).
- `iteration_count` = the cumulative count of agent dispatches issued so far in this Step for the
  tasks in this checkpoint's `task` label — stage count, not retry count: a task group dispatched
  as tester → coder is 2, tester → coder → reviewer under `step5_review_mode: checkpoint` is 3.
  There is no per-task retry loop in this Step to count instead; do not invent one to make this
  figure mean something it does not measure.
If `_pre5_ts` was never recorded (e.g. a resumed session that skipped the pre-flight block above),
OMIT `elapsed_wall_seconds` for every checkpoint in that run rather than measuring from an
arbitrary later point.

**Record one `task_metrics` entry per checkpoint**, tagged with the same `task` label
`budget_findings` uses at that same checkpoint (a single task number, or the comma list / range of
every task dispatched so far), carrying whichever of the four fields were actually computed.

#### Fallback — Agent-tool batch dispatch (hook_verified = false or workflow unavailable)

**Batch boundaries are a design choice, not an arithmetic one (ADR-0088, issue #241).** The tester
runs once per batch, before the coder, so an assertion that depends on another task's output cannot
see it if both sit in the same batch — the merge-back that would make it visible happens at the
batch boundary. Two rules follow, and reading the plan is the only way to apply them: do not put an
assertion in the same batch as the task it depends on, and do not split a red assertion from the
task that turns it green. #222's plan is the worked example — Task 3's `C7` must see Task 2's
vendored file, so they belong to different batches, while Task 1's `F10` and Task 2's vendoring
belong to the same one.

**When the two conflict, the first rule outranks the second (issue #247, ADR-0101).** They are not
jointly satisfiable on every plan, and #222's is the case: rule 1 forces task 3 into a later batch
than task 2, while rule 2 wants them together because `S1` reddens at task 2 and greens at task 3.
The reason for the ordering, and it is the part to carry forward rather than the verdict:
**evidence quality beats checkpoint tidiness.** Violating rule 1 makes an assertion fail for the
wrong reason, so the recorded RED proves nothing and the whole point of writing the test first is
gone. Violating rule 2 only leaves an intermediate checkpoint red — visible, explainable, and
resolved by a later batch in the same Step 5.

**Batch-dispatch policy (≥6 task blocks in plan):** **the number is `$openers`, from
`plan-tasks.sh --count-openers`, never `$tasks` (issue #242, ADR-0100).** `$tasks` over-counts by
design — a `## Tasks` section heading and every checkbox sub-step match it — so batching by it
produces ranges over tasks that do not exist; on #222's plan it says 38 where there are 7.

If `$openers ≥ 6`, do NOT dispatch the coder as a single monolithic block — the dispatch can
silently truncate halfway (context overflow, timeout) without a final report and without running
the closing gates. Split the dispatch into **batches of 2-3 task blocks**, numbered by their
`Task N` designations.

**If `$openers = 0` while `$tasks ≥ 1`: dispatch as a single block**, and say so:
> "Batch dispatch: the plan's tasks are not in the `Task N` form (`plan-tasks.sh --count-openers`
> returned 0), so batch ranges cannot be numbered. Dispatching as one block."

Two corpus plans, not three shapes, are in exactly that state — `deep-refactor-skill.md` (which
writes `### T1 —`) and `claude-md-slim.md` (which writes `### Step N —`, whose first heading is
`### Step 0 —`), the forms ADR-0070 §PTG9 and ADR-0069 §PTE2 exempt by name. Consuming `$openers`
without this branch would turn an over-batching bug into a batch-nothing one, which is #242
committed in the other direction.
If `$orc` is 2 or 3 the count did not run: treat it as this same case, single block, and report the
stderr.

1. Dispatch `tester` for batch 1 (tasks 1-N, where N ≤ 3), BEFORE this batch's coder
   (ADR-0049 §D1 — same ordering as the Workflow path's Stage 1). Pin `subagent_type: "tester"`,
   `model: "sonnet"`, and `isolation: "worktree"` explicitly (ADR-0049 §D6; `tester` has no
   `isolation` in its own frontmatter, F5, so an omitted value here means no worktree at all,
   ADR-0068 §D6, R-09). Do not pin `effort` here — the Agent tool has no such parameter at all
   (ADR-0068 §D7, issue #180); the effort table above documents the Workflow path's per-agent
   calibration only, not a value to carry over to this dispatch. Use the **Tester batch dispatch
   template** below — same brief contract as the Workflow path: SPEC requirement IDs via
   `spec-coverage.sh --list`, falling back to Success Criteria then to this batch's plan task
   text, never from implementation files.
2. Dispatch coder with batch 1 (tasks 1-N, where N ≤ 3). Before this dispatch, run the
   **Merge-back and base-fork audit** block above to merge this batch's tester worktree into the
   feature branch (same resolution site, same ordering as the Workflow path's Stage 1 → Stage 2).
   Pin `isolation: "worktree"` explicitly (ADR-0068 §D1, §D7 — there is no second mode; per the
   merge-back step just run, this coder forks from a `HEAD` that already contains the batch's
   failing tests) and use the **Single batch dispatch template** below, which carries the
   TEST-AUTHORING SCOPE marker verbatim.
3. Checkpoint between batches: run `verify.sh <root>` and check `git status` yourself
   as the orchestrator — do NOT trust the coder's report to decide whether to continue
   (it may be truncated or incomplete). Also run the `Anti-test-weakening gate — Step 5 →
   Step 6 (ADR-0047)` block at every batch checkpoint — the same command against the same
   cumulative diff, evaluated at more points, so an unattended run that weakens a test in
   batch 1 halts before burning batches 2..N. Also run the `Diff budget and scope check —
   Step 5 checkpoints (ADR-0052)` block at every batch checkpoint, `--tasks` accumulating
   every task number dispatched so far — advisory only, never a gate here either. Also run the
   `Task-level metrics — Step 5 checkpoints (ADR-0064, issue #118)` block at every batch
   checkpoint — metrics, not findings; never a gate, never surfaced at Gate 5.

   **An intermediate checkpoint can be legitimately red, and the chain had no concept of that until
   issue #247 (ADR-0101).** ADR-0049's flow assumes the tester reddens and the coder greens *within
   the same batch*, so a checkpoint should be clean. A third case exists: a **pre-existing guard in
   a file nobody in this batch touched**, whose premise the implementation changes and which a later
   task restores. #222's `S1` is the worked example — it reddens when task 2 vendors a skill into
   the population and greens when task 3 covers it, and the SPEC predicted it in those words.

   When a checkpoint is red, classify before reacting. **A red in a file this batch did not touch,
   which a later task in the plan restores, is expected**: name it, name the task that will green
   it, record it, and continue. **A red in this batch's own tests is not expected** and is the case
   the checkpoint exists for — stop and report. If neither description fits, stop: an unclassifiable
   red is the one that most needs a human.

   This is a reading rule, not a mechanism. An **expected-red declaration** in the plan, or a
   comparison against the previous checkpoint's failing set, would let the checkpoint decide rather
   than the reader — both were considered and deferred: the first needs a plan-side syntax, and
   issue #246 is the live warning about what a half-parsed one costs. `autopilot-build`'s circuit
   breaker is deliberately NOT relaxed in the meantime; it reads `step5-report.json` once after
   dispatch, so a red that greens inside Step 5 never reaches it.

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
4. Repeat steps 1-2 (tester, then coder) for batch 2 (tasks N+1…), and so
   on.
5. After the last batch: run the `Anti-test-weakening gate — Step 5 → Step 6 (ADR-0047)`
   block again, and run the `Requirement-ID coverage gate — Step 5 → Step 6 (ADR-0048)`
   block once here too — not at the per-batch checkpoint in item 3 above, where an
   uncovered ID is still the expected state — then final verification (`verify.sh`,
   `git status`, scope check against the plan) before transitioning to `step_6_review`.
   The `Diff budget and scope check — Step 5 checkpoints (ADR-0052)` block already ran at
   every batch checkpoint in item 3; no separate final pass is needed for it. Same for the
   `Task-level metrics — Step 5 checkpoints (ADR-0064, issue #118)` block.

For plans with ≤5 tasks monolithic dispatch is acceptable, but the controller-side
verification after dispatch is mandatory in all cases.

**Coder model override:** if `manifest.coder_model = "opus"` (or legacy `"fable"`), pass `model: "opus"` to every `Agent(subagent_type="coder", ...)` call in this dispatch. If `sonnet` or null, omit the `model` parameter (global coder.md applies).

**Tester batch dispatch template** (dispatched BEFORE this batch's coder — ADR-0049 §D1; pin
`subagent_type: "tester"` and `model: "sonnet"` explicitly on this `Agent` call, ADR-0049 §D6; no
`effort` pin — the Agent tool has no such parameter, ADR-0068 §D7, issue #180):
```
Read plan at <manifest.artifacts.plan> (tasks <FROM>-<TO> only).
Read SPEC.md at <manifest.artifacts.spec>.

Write failing tests for tasks <FROM>-<TO> only. Brief yourself from the SPEC's requirement IDs:
run `spec-coverage.sh --spec <manifest.artifacts.spec> --plan <manifest.artifacts.plan> --list`
(resolved exactly as in the Requirement-ID coverage gate below). If it lists one or more `R-NN`
IDs, write one failing test per listed ID this batch covers. Else if the SPEC declares no IDs,
brief from the SPEC's Success Criteria section verbatim. Else, brief from this batch's plan task
text. Never brief from implementation files — none exists yet for this batch.

That chain decides WHAT to assert. The plan decides WHERE and under what name, and you read it in
every case — never as a fallback. Work through tasks <FROM>-<TO> sub-step by sub-step and execute
every sub-step that creates or edits a test file. Those sub-steps are yours: the coder dispatched
after you is denied them by a PreToolUse gate, so a skipped sub-step is a sub-step nobody can do.
Where a sub-step says to confirm a failing assertion and stop, stop — a red assertion left red is
the deliverable, not an unfinished task.

Writes go under the dispatched worktree, never to an absolute path into the shared checkout: `isolation: worktree` bounds the working directory, not the filesystem, and an absolute path resolves out of it (ADR-0068 §D11, issue #245). Read the planning artifacts by absolute path; write by relative path.

Auto mode active. No intermediate HITL.
Return a report naming the requirement IDs (or Success Criteria / plan-task lines, per whichever
fallback fired) each test covers, plus which sub-steps you executed and which you leave to the
coder.
```

**Single batch dispatch template** (dispatched AFTER this batch's tester above; MUST carry the
TEST-AUTHORING SCOPE marker verbatim, ASCII hyphen, ADR-0049 §D3):
```
Read plan at <manifest.artifacts.plan> (tasks <FROM>-<TO> only).
Read ADR at <manifest.artifacts.adr>.
Read SPEC.md at <manifest.artifacts.spec>.
Read project CLAUDE.md at <manifest.artifacts.project_claude_md> (if not null).

TEST-AUTHORING SCOPE - the tester agent owns test files for this task. Do NOT create or edit tests.
Sub-steps in your tasks that create or edit test files were executed by the tester before this
dispatch and are NOT yours. Do not repeat them and do not edit those files. If that leaves a task
looking incomplete, say so in your report rather than closing the gap yourself. Make the red tests
green, except where the plan defers a red assertion to a later task: an assertion the plan defers
to a later task stays red, and your report says which one and why.
The red tests for tasks <FROM>-<TO> already exist — the tester agent wrote them before this
dispatch. You may not create or edit test files; if a test needs changing,
report it to the orchestrator instead of writing or editing it yourself.
Use your Pre-flight Pattern Classifier (ADR-0001) for every Edit operation.

Writes go under the dispatched worktree, never to an absolute path into the shared checkout: `isolation: worktree` bounds the working directory, not the filesystem, and an absolute path resolves out of it (ADR-0068 §D11, issue #245). Read the planning artifacts by absolute path; write by relative path.

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

Set `step5_mode: "agent_batch"` in the manifest when the fallback activates (via bash sed substitution on the additive field — NOT via Edit tool, NOT via manifest-set-flag.sh which is boolean-only). <!-- path-rule-exempt: negated -- says NOT to use this helper for the step5_mode write, describing what not to do -->

### Step 6 — Review cycle (conditional on hook_verified)

**Dispatch mode selection:**
- If `manifest.hook_verified = true`: use Workflow dispatch path (below). Set `step6_mode: "workflow"` via bash sed substitution.
- If `manifest.hook_verified = false` or `null`: use skill fallback (below). Set `step6_mode: "skill_fallback"` via bash sed substitution.

#### Workflow dispatch path — Step 6 review cycle (hook_verified = true)

Send the following workflow prompt to the session:

```
ultracode — use a workflow to run a parallel review-and-fix cycle.
IMPORTANT: The workflow script must be deterministic — do NOT use Date.now(), new Date(), or Math.random(). These calls throw at runtime and break workflow resume (CC 2.1.172 removed the validation warning but the runtime constraint remains).
IMPORTANT: every agent() call pins BOTH its model and its effort explicitly (reviewer → sonnet/high, fix agents → opus plus the FIX_EFFORT value for their type). A workflow subagent with agentType but no model inherits the main-loop (CLI session) model, not the agent frontmatter. `opts.effort` behaves identically — the Workflow tool documents it as "omit to inherit the session effort" — so an omitted effort silently runs the whole review-and-fix cycle at the orchestrator's level and discards each agent's frontmatter calibration. Omit neither.

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
  agent(`
    Review all files modified in this implementation cycle.

    The approved implementation plan is at <manifest.artifacts.plan>. Read it, and include PLAN
    CONFORMANCE as an explicit lens: where the implementation departs from what the plan
    specified, say so as a finding (ADR-0073 §D2, issue #178).
    A departure is NOT automatically a defect — a plan is written before the code is read, and
    "the coder chose a better approach" is a frequent and legitimate outcome. Report it at the
    severity the DEPARTURE ITSELF warrants, judged on the code, not on the fact of departing.
    step5-report.json's plan_deviations array lists the departures the coder declared; treat it
    as a starting point, never as the complete set, since it is a self-report.

    Return a JSON array of findings matching FINDINGS_SCHEMA.
    Key: "findings". No other top-level keys.
  `, { agentType: "reviewer", model: "sonnet", effort: "high" })

Phase 2 — Group findings by file (in-script, no agent):
  const findings = JSON.parse(reviewResult).findings ?? [];
  const byFile = {};
  for (const f of findings) {
    if (!byFile[f.file]) byFile[f.file] = [];
    byFile[f.file].push(f);
  }
  const fileGroups = Object.values(byFile);
  // agentType is chosen at runtime from fix_type, so effort cannot be a literal — it is
  // looked up by the same key. Values mirror each agent's own frontmatter, exactly as the
  // Step 5 table does; they are not linked, so a frontmatter change means changing this too.
  const FIX_EFFORT = { debugger: "high", refactorer: "medium", coder: "xhigh" };

Phase 3 — Fix in parallel per file group:
  // model: "opus" deliberately overrides the sonnet frontmatter of coder/refactorer/debugger.
  // This is a cross-skill convention, not drift here: same override in review-triage-fix
  // (its "**Model override — branches on the variant declared in Step 0, item 5:**" block —
  // fix agents make judgment calls without a structured plan, Opus reduces the risk of
  // introducing new issues) and in deep-refactor (its "model: opus requirement"
  // section), decided in ADR-0018 § Dispatch model. Model and effort come from different
  // places on purpose — model overridden to opus, effort still each agent's frontmatter value
  // via FIX_EFFORT — so the mismatch below is intended, not a leftover.
  // Parallel dispatch is safe ONLY because Phase 2 grouped findings by file — one file per agent,
  // so no two agents ever edit the same file. ADR-0018 otherwise requires fix phases to be
  // sequential precisely to avoid that conflict. Change Phase 2's grouping and this breaks.
  // The grouping alone is not enough (issue #83): it bounds where the FINDINGS are, not where the
  // EDITS land. An agent fixing an import or a shared helper could write a file that was nobody's
  // assigned file, and two agents would then collide on it. Hence the write-scope constraint in
  // the prompt below. It is an instruction, not an enforcement — no hook constrains a subagent's
  // write paths by file today (ADR-0016 Addendum 2026-07-25c).
  await parallel(fileGroups.map(group => () =>
    agent(`
      Fix the following findings in ${group[0].file}:
      ${JSON.stringify(group, null, 2)}
      Use Pre-flight Pattern Classifier (ADR-0001) for every Edit.

      WRITE SCOPE — you may edit ONLY ${group[0].file}. Other agents are fixing other files in
      parallel right now, and editing outside your file can silently lose their work.
      If resolving a finding needs a change in any other file, do NOT edit that file: record it
      in "deferred" and leave the finding in "skipped". Reporting a deferred change is the
      correct outcome, not a failure.
      A hook enforces this. If a write is blocked with a write-scope message, that is the guard
      working as intended, not an error on your part: record it in `deferred` and carry on with
      your own file. Do not retry, do not reach for another tool, do not try to route around it.

      Return: { "fixed": [<id>, ...], "skipped": [<id>, ...],
                "deferred": [{ "file": "<path>", "needed": "<what change and why>" }],
                "notes": "<string>" }
    `, { agentType: group[0].fix_type, model: "opus", effort: FIX_EFFORT[group[0].fix_type], isolation: 'worktree' })
  ));

Phase 4 — Re-review:
  agent(`
    Re-review all files that were fixed in Phase 3.
    Confirm each finding from Phase 1 is resolved or document why it was skipped.
    Also read every "deferred" entry the fix agents returned — those are cross-file changes they
    were forbidden to make. For each, state whether the need is real. Do NOT act on any of them:
    a deferred item is carried to the report, never fixed here.
    Return: { "resolved": [<id>, ...], "remaining": [<id>, ...],
              "deferred_confirmed": [{ "file": "<path>", "needed": "<string>", "real": true|false }],
              "summary": "<string>" }
  `, { agentType: "reviewer", model: "sonnet", effort: "high" })

Final subagent writes <project_root>/.claude/step6-report.json:
{
  "step6_mode": "workflow",
  "findings_count": <n>,
  "resolved_count": <n>,
  "remaining_count": <n>,
  "remaining_ids": [...],
  "deferred": [{ "file": "<path>", "needed": "<string>", "real": true|false }],
  "summary": "<string>"
}
`deferred` aggregates the cross-file changes fix agents were forbidden to make (issue #83),
confirmed or dismissed by Phase 4. Additive — a report written without the key stays valid and
the orchestrator reads it as empty.
```

After the workflow completes:
1. Read `<project_root>/.claude/step6-report.json`.
2. If absent or malformed → fall back to skill fallback below (record `step6_mode: "skill_fallback"`).
3. If `remaining_count > 0` → present unresolved findings to user before transitioning.
4. If `deferred` is non-empty, present the entries with `real: true` alongside them, labelled
   "cross-file changes not applied — a fix agent needed them outside its assigned file". They are
   findings for the user to decide on, never a failure signal and never auto-fixed here.
5. Run the Interface immutability gate (below) over the cumulative diff since `$_pre5` — after
   the fix cycle, before the review is accepted.
6. Evaluate Gate 5.05 (see §5 Gate 5.05 block).

#### Skill fallback (hook_verified = false or workflow unavailable)

```
Use the review-triage-fix skill.
Target: files modified by coder in step_5_implementation (see manifest.artifacts.plan completion section).
Execute review-triage-fix v1.2 with Add+Remove rule.

Return final report.
```

After review (or skip), run the Interface immutability gate (below) over the cumulative diff
since `$_pre5`, then evaluate Gate 5.05 (see §5 Gate 5.05 block).

#### Interface immutability gate — Step 6, before the review closes (ADR-0053)

Checks that the diff accumulated since Step 5 began has not removed or rewritten a signature the
project declared protected in `.claude/protected-interfaces`. Runs at the END of Step 6, after
whichever review/fix path just ran — after the code exists, before the review is accepted (§D5) —
because a fix agent's own edit can break a protected interface exactly as easily as the original
implementation could.

**Directory-family contract table (§D3). Read this before copying an idiom from any of the four
scripts below — the reporter/checker confusion in this family has now been written down three
times (ADR-0048 §D7, ADR-0052, and here) — do not copy one row's idiom into another's block:**

| script | contract | caller idiom |
|---|---|---|
| `weakening-scan.sh` | reporter | grep stdout for `^WEAKENED` |
| `diff-budget-check.sh` | reporter | grep stdout, `CLEAN` sentinel |
| `spec-coverage.sh` | checker | branch on exit code |
| `interface-check.sh` | checker | branch on exit code |

**Resolution** (`staging/plugin/scripts/`, deploying to `~/.claude/hooks/` — the standalone-CI
shape `secret-scan.sh`/`dependency-scan.sh` already use, **not** the
`skills/concept-to-code/scripts/` shape `spec-coverage.sh`/`diff-budget-check.sh` use, because
this script's inputs are a project-level declaration file plus a diff, never a chain artifact —
ADR-0053 Task 2, mirroring ADR-0048 §A6's reasoning in the opposite direction):
```bash
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] \
   && [ -f "$CLAUDE_PLUGIN_ROOT/scripts/interface-check.sh" ]; then
  _icheck="$CLAUDE_PLUGIN_ROOT/scripts/interface-check.sh"
elif [ -f "$HOME/.claude/hooks/interface-check.sh" ]; then
  _icheck="$HOME/.claude/hooks/interface-check.sh"
else
  _icheck=""     # gate did not run — report it, do not infer a clean result
fi
```

**Invocation and exit-code idiom** (checker — branch on the exit code, never grep stdout for a
sentinel the way the two reporters above are handled. The diff MUST be generated with
`--no-renames`, per the script's own header — git's default rename detection can collapse a
same-content file move into a rename record with no `-`/`+` lines at all, hiding a real
relocation from a purely textual check):
```bash
if [ -n "$_icheck" ]; then
  _iout=$(git diff --no-renames "$_pre5" | bash "$_icheck" --root "<project_root>" 2>&1)
  _irc=$?
fi
```
`_irc = 0` → no protected interface broken, including the common case where the project declares
none at all (inert by construction, ADR-0053 §D1 — the script itself is silent on both streams
when `.claude/protected-interfaces` is absent or comment/blank-only). `_irc = 3` → one or more
protected interfaces broken, `_iout` carries the `PROTECTED<TAB><entry><TAB><file>:<line><TAB>removed|changed`
lines. `_irc = 2`, or `_icheck` empty: unavailable, fail-open (see Policy).

**Do not copy `weakening-scan.sh`'s or `diff-budget-check.sh`'s branching into this block, and do
not copy this block's exit-code branching into theirs.**

**Policy — this gate BLOCKS** (ADR-0053 §D2). Unlike every array in `step5-report.json` above
except `weakening_findings`, do not soften this to advisory to match `suspect_findings` or
`budget_findings` — the signal here is mechanical (a protected signature is either still present
or it is not), which is exactly why it is allowed to block where a heuristic finding is not:
- Attended: present the `PROTECTED` findings and do NOT proceed to Gate 5.05 without user
  acknowledgment.
- Autopilot (`manifest.autopilot = true`): halt — do not proceed to Gate 5.05.
- `_irc = 2`, or `_icheck` empty (script did not resolve): fail-open, visibly — note it in the
  summary shown at Gate 5.05 and proceed.

### Step 7 — Commit (invoke `commit` skill, always)

**Step 7.0 — collapse the Step 5 snapshots first (issue #249, ADR-0104).**

By the time Step 7 runs, the feature is **already fully committed** — by the orchestrator, under
messages chosen for a mechanical purpose (`chore(step5): snapshot <stage> worktree (<agent_type>)`,
one per stage per task group). The staged set is then the manifest and little else, so the `commit`
skill reads `git diff --staged` and faithfully describes a manifest state change. **The commit the
whole skill exists to produce has nothing left to describe.**

Nobody chose that. ADR-0068 §D5 made the orchestrator the committer so the next stage's worktree
could fork from a `HEAD` containing the previous stage's output; ADR-0049 §D1 ordered
tester-before-coder, which doubled the snapshots. Two correct decisions composing into a third
behaviour.

**Step 5 is over, so their purpose is spent** — nothing forks from these commits again. Collapse
them back into the index so `commit` sees the whole feature as one diff:

<!-- fence-contract: c2c-step7-snapshot-collapse -->
```bash
# ADR-0133 §D1 (issue #394): the body between the two FENCE_BASH lines runs under BASH, not under
# the host shell. No `export` prologue — this body binds everything it reads, from the substituted
# `<baseline>` placeholder. Terminator at COLUMN 0; an indented one is swallowed into the
# here-document and destroys this fence's exit code silently, which on a fence that rewrites branch
# history is the last place a lost exit code is affordable.
bash <<'FENCE_BASH'
# Free variable: <baseline> is manifest.recovery_baseline_sha.
git rev-parse --git-dir >/dev/null 2>&1 || { echo "COLLAPSE_NOREPO"; exit 3; }
_b="<baseline>"
case "${_b:-}" in ""|null) echo "COLLAPSE_SKIP noBaseline"; exit 0 ;; esac
git cat-file -e "$_b" 2>/dev/null || { echo "COLLAPSE_SKIP baselineGone"; exit 0; }
git merge-base --is-ancestor "$_b" HEAD 2>/dev/null || { echo "COLLAPSE_SKIP notAncestor"; exit 0; }
_n=$(git rev-list --count "$_b"..HEAD 2>/dev/null || echo 0)
[ "${_n:-0}" -gt 0 ] || { echo "COLLAPSE_SKIP noCommits"; exit 0; }
_foreign=$(git log --format='%H %s' "$_b"..HEAD \
  | grep -vE '^[0-9a-f]+ chore\(step5\): snapshot .* worktree \(' \
  | grep -vE '^[0-9a-f]+ chore\([^)]*\): (record|snapshot) ' | head -1)
[ -z "$_foreign" ] || { echo "COLLAPSE_SKIP foreignCommit ${_foreign%% *}"; exit 0; }
git reset --soft "$_b" || { echo "COLLAPSE_NOREPO"; exit 3; }
echo "COLLAPSED $_n $_b"
exit 0
FENCE_BASH
```

- `COLLAPSED <n> <sha>` → emit `"Step 7: collapsed <n> Step 5 snapshot commit(s) — the feature is
  now one staged diff."` and invoke `commit` below.
- `COLLAPSE_SKIP <reason>` → say which reason and invoke `commit` unchanged. **`foreignCommit` is
  the one worth reading**: the range holds a commit the chain did not make, and folding it away
  would take its message with it.
- exit 3 → report; do not retry, and invoke `commit` unchanged.

**A soft reset keeps the working tree and the index exactly as they are** — no content is created,
changed or deleted, only the branch tip moves, and the collapsed tips stay in the reflog. That is
why this is safe to do without a gate; `commit`'s own Step 4 gate still shows the resulting diff
before anything is written.

**The guards are the design, not caution.** Resetting past a commit the chain did not make would
fold a human's separate commit — and its message — into the feature commit; resetting to a
non-ancestor baseline would detach the branch from its own history (issue #244's state, which this
refuses rather than inherits).

**Step 7.0b — archive this chain's own SPEC and repoint the manifest (issue #267, ADR-0106).**
Runs after the collapse above and before the invocation below.

ADR-0096 archives the **outgoing** SPEC when a new chain is about to overwrite the root slot —
archive-on-**displacement**. That means a chain's SPEC is archived only if a LATER chain happens to
displace it, so **the most recent chain's SPEC is never archived**. This is
archive-on-**completion**, the other trigger. The two compose safely: `spec-archive.sh` compares by
content, so the second call on the same SPEC reports `ALREADY` and writes nothing.

```bash
bash ~/.claude/skills/concept-to-code/scripts/spec-archive.sh "<project-root>" "<topic-slug>"
```

- `ARCHIVED <path>` or `ALREADY <path>` → repoint the manifest at that path:
  `bash ~/.claude/skills/concept-to-code/scripts/manifest-set-artifact.sh <manifest-path> spec <path>`.
  Without this the manifest keeps naming `<project-root>/SPEC.md`, a single mutable slot the next
  chain overwrites — measured across all 41 existing manifests, which is what #267 records.
- `NOSPEC`, `COLLISION`, or exit 3 → **leave the pointer as it is** and say which. A pointer at a
  slot is today's behaviour, not a regression; a pointer at an archive that was never written is.

**Step 7.0c — transition to `completed` (issue #410, ADR-0135).** Runs after 7.0b, not before:
`manifest-set-artifact.sh` has no terminal guard, so a repoint issued after the transition would
succeed silently and land outside the commit — the same defect one write over, in a step whose whole
subject is this defect.

**Every manifest write in this step precedes the `commit` invocation, and this transition is the
last of them.** A manifest write after `commit` is an uncommitted change nothing ever commits.

```bash
# Standard path: terminal before the commit invocation below (issue #410, ADR-0135).
bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh "<manifest-path>" completed completed
```

A non-zero exit means the manifest is not terminal: report and stop — do not invoke `commit`.
Step 7.1 (below) is the backstop for a commit outcome, not the primary guard for this.

**Both new paths must be passed to `commit` explicitly.** The collapse above leaves everything
staged, and `commit`'s Step 1 then takes the staged set only — so the freshly-written archive
(untracked) and the freshly-repointed manifest (tracked, modified after staging) would both be
excluded. That is what `--include` exists for (ADR-0071 §D2), and Gate 4.0 already uses it the same
way.

**IMPORTANT — use the `Skill` tool, NOT the `Agent` tool.** `commit` is a **skill**, not an agent.

```
Use the commit skill (invoke via Skill tool, not Agent tool).
Context hint: "<topic-full-title> (ADR: <manifest.artifacts.adr>)"
Arguments: --include <archived-spec-path>,<manifest-path>
```

The skill manages the HITL gate (AskUserQuestion), Conventional Commits message generation, and the PR option internally. The orchestrator does nothing after invocation: the skill closes the cycle on its own.

**Step 7.1 — classify what `commit` did (issue #410, ADR-0135 §D3).**

The verdict is read off the manifest on disk, never off the skill's own report: `commit` emits no
machine-readable outcome, and an agent's self-report is not a gate (ADR-0047 §A3). "Nothing to
commit" and "declined" are told apart the same way — not by asking what happened, but by whether
the manifest is committed.

<!-- fence-contract: c2c-step7-commit-outcome -->
```bash
# ADR-0133 §D1 (issue #394): the body between the two FENCE_BASH lines runs under BASH, not under
# the host shell. No `export` prologue — this body reads only the substituted `<manifest-path>`
# placeholder, no caller-bound variable crosses the process boundary. Terminator at COLUMN 0; an
# indented one is swallowed into the here-document and destroys this fence's exit code silently,
# and this fence's whole contract is its exit code (ADR-0135 §D3).
bash <<'FENCE_BASH'
_m="<manifest-path>"
[ -f "$_m" ] || { echo "COMMIT_OUTCOME_NORUN noManifest"; exit 3; }
_d=$(dirname "$_m")
git -C "$_d" rev-parse --git-dir >/dev/null 2>&1 || { echo "COMMIT_OUTCOME_NORUN noRepo"; exit 3; }
_cs=$(grep '^current_step:' "$_m" | head -1 | sed -e 's/^current_step:[[:space:]]*//' -e 's/^"//' -e 's/"[[:space:]]*$//')
_st=$(grep '^status:' "$_m" | head -1 | sed -e 's/^status:[[:space:]]*//' -e 's/^"//' -e 's/"[[:space:]]*$//')
if [ "$_cs" != "completed" ]; then echo "COMMIT_NONTERMINAL current_step"; exit 1; fi
if [ "$_st" != "completed" ]; then echo "COMMIT_NONTERMINAL status"; exit 1; fi
_gs=$(git -C "$_d" status --porcelain -- "$(basename "$_m")")
if [ -z "$_gs" ]; then echo "COMMIT_OK"; exit 0; fi
case "$_gs" in
  '??'*) echo "COMMIT_UNCOMMITTED untracked"; exit 1 ;;
  *)     echo "COMMIT_UNCOMMITTED modified";  exit 1 ;;
esac
FENCE_BASH
```

- `COMMIT_OK` → proceed to the post-commit actions below. This is also the verdict on a resumed or
  already-committed run — `manifest-transition.sh` is a same-to-same no-op, `commit` reports
  nothing to commit, and the manifest is already committed and terminal, so this is a **pass, not a
  decline**.
- `COMMIT_UNCOMMITTED untracked|modified` or `COMMIT_NONTERMINAL current_step|status` → stop and
  report: name `<manifest-path>`, say the tree is uncommitted (or, for `COMMIT_NONTERMINAL`, that
  7.0c did not take effect), and say **no rollback is attempted and no transition is added, because
  `completed` is absorbing** (ADR-0078) — terminal states have no legal way back. The post-commit
  push, the PROJECT.md update and the cost snapshot do **not** run.
- exit 3, `COMMIT_OUTCOME_NORUN <reason>` → report **did not run**, naming the reason — not a pass,
  and the post-commit actions do not run either.

**Post-commit push (conditional on Step 7.1 reporting `COMMIT_OK` AND `manifest.initial_commit_push = "push"` AND `manifest.autopilot != true`):**

This block is skipped unconditionally when `autopilot = true` — `concept-to-code`'s own autopilot
mode never pushes unattended (ADR-0020 D2). No separately-orchestrated automated publish flow is
threaded through here: any such flow runs entirely outside this block, through
`project-conductor`'s `publish-feature.sh`, strictly after this chain hands back a local commit
(ADR-0022 D5/D6) — this file stays agnostic to that outer orchestration by design.

After Step 7.1 reports `COMMIT_OK`, if `manifest.initial_commit_push = "push" AND manifest.autopilot != true`:

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

If PROJECT.md was loaded at Gate 0 AND Step 7.1 reports `COMMIT_OK`:

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

After Step 7.1 reports `COMMIT_OK`:

**Cost snapshot — chain end:** compute and print the spend for this chain run.
```bash
python3 ~/.claude/scripts/usage-snapshot.py --diff "chain-<topic-slug>" --log-to ~/.claude/chain-eval.md 2>/dev/null || true
```
Emit the diff output inline in the final report. If the snapshot file is missing (e.g. chain was resumed mid-run), skip silently.

The manifest is already terminal — 7.0c transitioned it to `completed` before the commit invocation
above. Do not transition again here. Write final report.

---

### Express path — Steps E1–E4 (chain_path=express)

No sub-agents. No fresh session. No SPEC, ARCH, or ADR. The orchestrator executes everything directly.

**No worktree isolation, by design** — Step E2 dispatches no sub-agent: the orchestrator executes the approved plan directly in this session, so there is no worktree to isolate. ADR-0068 §D7 requires every *dispatch* to pin that value explicitly; a path with no dispatch is outside it. The consequence is real and is the price of the single-session design (ADR-0017): a failure during E2 leaves partial edits in the working tree, so recovery is `git status` and a manual reset, not discarding a worktree.

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

```bash
# Express path: terminal before the commit invocation below (issue #410, ADR-0135).
bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh <manifest-path> completed completed
```
Invoke `commit` skill (Skill tool, not Agent).

Step 7.1's commit-outcome check does not apply on this path: Express passes no `--include` and the
manifest is never committed at all, so applying that check would halt every Express run. See issue
#422.

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
  1. Transition `step_h3_execute → gate_h3_verify` (call `~/.claude/skills/concept-to-code/scripts/manifest-transition.sh` now).
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

```bash
# Hybrid path: terminal before the commit invocation below (issue #410, ADR-0135).
bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh <manifest-path> completed completed
```
Invoke `commit` skill (Skill tool).

Step 7.1's commit-outcome check does not apply on this path: Hybrid passes no `--include` and the
manifest is never committed at all, so applying that check would halt every Hybrid run. See issue
#422.

---

## 5. HITL gates

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
`_erc = 0` → every declared dependency is `provisioned: true`, or none were declared (no Gate 2c
line at all — this whole gate is skipped, §D5). `_erc = 1` → at least one is not provisioned;
`_eout` carries `UNMET<TAB><name><TAB><kind><TAB><state>` lines, and the stderr captured in
`$_edep_err` names the human action required for each. `_erc = 2`, or `$_edep` empty: the gate did
not run — proceed to the `AskUserQuestion` below anyway, noting automatic verification was
unavailable, rather than silently treating it as clean.

If `_erc = 0` (and `_edep` resolved): write `external_dependencies` into the manifest from the
declared lines (each `provisioned: true`) and proceed directly to Gate 3 — nothing for a human to
decide, D2's check already passed.

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
  <spec>,<manifest.artifacts.adr>,<manifest.artifacts.plan>,<manifest-path>`.
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
`requirement_coverage` (its `uncovered` list), `checkpoint_reviews`, `tests_written_by`,
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

Check whether any UI files were modified in this cycle:
```bash
git diff --name-only HEAD | grep -E '\.(swift|html|css|tsx|jsx|vue)$'
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
```
Agent({ subagent_type: "reviewer",
        prompt: "SCOPE: silent-failure-hunter — error handling audit.\nReview the following files for: empty or swallowed catch blocks, ignored return values or Result types, optional chaining masking failures, unhandled Promise rejections, broad exception catches that hide root causes, and error objects logged without actionable context.\nReport only — do not edit any file. Output findings grouped by severity: CRITICAL / IMPORTANT / SUGGESTIONS.\nFiles: <modified-file-list-from-manifest>" })

Agent({ subagent_type: "reviewer",
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
