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
- The **only** skills invokable inside this chain: `interview-driver`, `design-brainstorm` (gate 1b only), `macos-ux` (gate 1c only, conditional on macOS/SwiftUI SPEC detection), `claude-design-brief` (gate 1d only), `claude-md-generator`, `review-triage-fix` (step 6 / H4 only, optional), `ui-layout-audit` (gate 5.05 only, conditional on UI files present), `deep-refactor` (gate 5.1 only, conditional on user choice), `commit` (step 7 / E4 / H5, always), superpowers skills (Express step E1 only, inside plan mode); `reviewer` agent with specialized inline prompts (gate 5.06 only, conditional on user choice: silent-failure-hunter scope + type-design-analyzer scope)

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

   **Gate CDX (Codex assist — chain-wide, optional, no transition):** ask once via
   `AskUserQuestion`: "Use Codex instead of Claude for review dispatch in this run? (RTF review
   cycles and Step 5 checkpoint reviews only — coding and testing stay on Claude.)" Options:
   `[no]` "No — Claude only (current behaviour)" / `[yes]` "Yes — use Codex for review, with a
   gate if it's unavailable".
   - `[no]` → `manifest.use_codex_review` stays `false` (already seeded by `manifest-init.sh`).
     Byte-identical to today's behaviour for every run that does not opt in.
   - `[yes]` → set it via
     `~/.claude/skills/concept-to-code/scripts/manifest-set-flag.sh <manifest> use_codex_review true`.
   **Decision is exclusively the user's: never auto-applied**, and this gate does not fire under
   `--autopilot` — autopilot runs are unattended, and this feature is not extended to unattended
   runs in this pass; `manifest.use_codex_review` stays at its seeded `false` for every autopilot
   run, identically to today.
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

Legal transition pairs (51 total — 28 standard + 6 express + 17 hybrid, including Gate 0d routing, Step 4.5 tracer-bullet routing, Gate 1d/H1d Claude Design routing, and direct-close shortcuts). Four standard pairs through `gate_5_review_decision` were removed by issue #265 (ADR-0105): nothing ever entered that state, because Gate 5 is an inline sub-gate:
- Standard: 28 pairs total — 25 pairs preserved from the prior reconciliation (the 28 pre-existing pairs, minus the four `gate_5_review_decision` pairs removed by ADR-0105, plus 1 new pair for Step 4.5's
  amber / "red → reduce scope" route (ADR-0057): `ready_for_implementation→gate_2_architecture_review`.
  Green and "red → continue anyway" reuse the existing `ready_for_implementation→step_5_implementation`
  pair; hand-code reuses the existing unconditional any-state-to-`aborted` wildcard. Checked against
  the ADR-0027 Gates-0c/0d lesson (pairs can be written but structurally unreachable) before assuming
  new pairs were needed at all — Gate 2b and Gate 5.05/5.06 are already inline sub-gates with no
  dedicated state, and Step 4.5 follows the same shape, so only this one pair was actually missing),
  plus 3 new pairs for Gate 1d's Claude Design decision (VCS-052, ADR-0181):
  `gate_1b_brainstorm_decision→gate_1d_claude_design_decision`, `gate_1c_macos_ux_decision→gate_1d_claude_design_decision`,
  `gate_1d_claude_design_decision→step_2_architecture`. The prior direct exits
  `gate_1b_brainstorm_decision→step_2_architecture` and `gate_1c_macos_ux_decision→step_2_architecture`
  stay declared and legal but unreachable from the live routing prose now that Gate 1d always fires
  between them and the architect (same ADR-0027 precedent: a pair can be declared without being
  currently instructed).
- Express (new): `step_0_init→step_e1_plan`, `step_e1_plan→step_e2_execute`, `step_e2_execute→gate_e3_verify`, `gate_e3_verify→step_e4_commit`, `step_e4_commit→completed`, `gate_e3_verify→completed`
- Hybrid: `step_0_init→step_h1_interview`, `step_h1_interview→gate_h1_spec_review`, `gate_h1_spec_review→step_h2_plan`, `gate_h1_spec_review→gate_h1b_brainstorm`, `gate_h1_spec_review→step_h1_interview`, `gate_h1b_brainstorm→step_h2_plan`, `gate_h1b_brainstorm→gate_h1c_macos_ux`, `gate_h1c_macos_ux→step_h2_plan`, `step_h2_plan→step_h3_execute`, `step_h3_execute→gate_h3_verify`, `gate_h3_verify→step_h4_review`, `gate_h3_verify→step_h5_commit`, `step_h4_review→step_h5_commit`, `step_h5_commit→completed`, plus 3 new pairs for Gate H1d (VCS-052, ADR-0181): `gate_h1b_brainstorm→gate_h1d_claude_design`, `gate_h1c_macos_ux→gate_h1d_claude_design`, `gate_h1d_claude_design→step_h2_plan`

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
- `~/.claude/skills/concept-to-code/scripts/manifest-transition.sh <manifest> <new-step> [<new-status>]` — performs legal state transitions atomically (51 pairs).
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
it is a no-op on the genuinely-empty one **because `spec-archive.sh` looks for the file before it
validates the slug**. That ordering is load-bearing and was wrong until issue #455: on an empty root
`gate0-detect.sh` reports `spec_topic_slug=unknown`, the fence passes it through, and the slug guard
used to refuse with exit 3 — whose contract below is HALT. So the sentence above described the
bootstrap path and the bootstrap path was the one that could not get past this step. If you move
that check in `spec-archive.sh`, you are re-breaking this claim (ADR-0152).

**It is also a no-op on a SPEC.md that EXISTS but is already archived byte-identically, regardless
of what slug it carries (issue #408, ADR-0164).** 69 of 75 archived SPECs carry no `**Topic slug:**`
marker, so `spec_topic_slug=unknown` for them too — not only for the bootstrap case above. Until
#408, `spec-archive.sh` checked the slug before comparing content, so an unmarked SPEC that was
provably already archived still HALTed. The script now compares content first; the slug is examined
only when a write is actually about to happen. Do not reorder those two checks back — that reorder
is exactly what re-breaks this claim.

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
- **`3`** → **HALT.** Print the script's stderr — it names the actual cause (`SPECARCHIVE_NOSCRIPT`,
  a malformed slug shape, a SPEC that must be archived but has no name to archive it under, or a
  filesystem failure) and it is never the same cause twice. Only when the fence itself printed
  `SPECARCHIVE_NOSCRIPT` — the script is not deployed — is the remedy the sync command
  (`bash staging/sync-to-claude.sh --apply`); every other exit-3 cause is a declined input, not a
  missing script, and the sync remedy does not fix it (issue #408).

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
   grep -qiE '^\*\*[[:space:]]*topic[[:space:]]+slug[[:space:]]*:\*\*' "<project-root>/SPEC.md" || {
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
- `MACOS_DETECTED` → transition `gate_1b_brainstorm_decision → gate_1c_macos_ux_decision`. Present **Gate 1c** (see §5 Gate 1c block). After Gate 1c resolves, transition `gate_1c_macos_ux_decision → gate_1d_claude_design_decision`.
- `NOT_MACOS` → transition `gate_1b_brainstorm_decision → gate_1d_claude_design_decision`. No Gate 1c shown.

**Gate 1d (runs after Gate 1c resolves, or directly after Gate 1b when `NOT_MACOS`; unconditional and optional, VCS-052/ADR-0181 — see §5 Gate 1d block):** present **Gate 1d**. After Gate 1d resolves, transition `gate_1d_claude_design_decision → step_2_architecture`. Dispatch architect.

**Native memory (VCS-056, ADR-0183):** architect carries `memory: project` and manages its own
persistent notes — no inject/harvest step here, no `PRIOR AGENT NOTES` placeholder in the brief.

**Cost note (Max 20x profile):** for **routine / low-risk** ADRs, dispatch architect with override `model: sonnet` (the `model` parameter of the Agent tool); reserve **Opus** (default frontmatter) for **complex / novel / high-risk** designs. Opus resolves via `ANTHROPIC_DEFAULT_OPUS_MODEL` to `claude-opus-4-8[1m]` (fast mode: 2x standard cost, 2.5x speed). Consistent with the `opusplan` philosophy: Opus where reasoning matters, Sonnet for routine execution.

<!-- dispatch-site: step2-architect class=inline exempt: the architect's report is parsed for named field markers whose absence already hard-aborts, so an early read fails loud rather than green -->
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
If a Claude Design artifact exists, read it at <manifest.artifacts.design> and any declared
local export. Its Binding decisions are a constraint on the plan, not an input to weigh:
every screen its Screens table names must be cited by a plan task, or the ADR must state why
it is not being built.
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
Include any `EXTERNAL DEPENDENCY:` lines (ADR-0060) and TEST-CMD CANDIDATE (see architect.md Output Format).

[IF manifest.xcode_project=true — add this block to dispatch, otherwise omit:]
XCODE PROJECT: Include a dedicated implementation task for Xcode project scaffolding (Swift 6, SwiftUI, Package.swift or .xcodeproj, directory structure, target configuration, bundle ID).
```

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
2. **The narrative block does NOT go in CLAUDE.md (issue #380, ADR-0136).** CLAUDE.md is loaded in
   full into every orchestrator turn and re-injected after every `/compact`; a full narrative block
   per feature made this repository's own file ~75,000 tokens per turn, 21.5% of the orchestrator's
   cache-read volume. Measured re-growth is ~58 lines per feature, so a condensed file doubles in
   four features. **This step is what stops that.** Compose the block and append it to the
   narrative archive instead:
   ```markdown
   ## Decisions from the <topic-full-title> chain (<ADR-NNNN>)

   <skill-or-feature description, one sentence>: `<invocation or path>`.

   Key architectural decisions:
   - **<Decision 1 label>:** <one-line summary>
   - **<Decision 2 label>:** <one-line summary>
   [... 4-8 bullets total ...]

   Detail: `<relative path to ADR file>`.
   ```
   Append it to `<project-root>/docs/chain-decisions.md` if that file exists. If it does not, this
   project has not adopted the split: append the block to CLAUDE.md exactly as before and skip
   step 3. The archive's presence is the switch, so no project is broken by this change.
3. **One index line, always, and a CLAUDE.md Rules line only sometimes.** The two go to different
   files, and only the second reaches `<project-root>/CLAUDE.md.proposed`:
   - **Index line — always.** Append it to `<project-root>/docs/chain-decision-index.md` if that
     file exists (ADR-0163); if it does not, this project has not adopted the split, so append it
     under `## Chain decision index` in `CLAUDE.md.proposed` exactly as before. The index file's
     presence is the switch, the same one step 2 uses for the archive, so no project is broken by
     this change. Either way the form is unchanged:
     `- **<ADR-NNNN>** — <the single thing it decided, one clause> → \`<path to the ADR>\``.
     The index and the archive must stay the same size: one block appended, one index line
     appended.
   - **Rules line — only when the ADR establishes a recurring invariant that is not already in
     `## Rules`.** Read the existing list first. Most features establish no new rule and add no
     line; that is the normal case and adding a near-duplicate is the failure this step exists to
     prevent. When one is genuinely new, state the rule, a one-clause reason, and the ADR — the
     reason is not optional, because a rule without its counterexample is a slogan.
4. **Ceiling guard.** Run `wc -l < CLAUDE.md.proposed`. If the count exceeds 400, prepend to the
   Gate 3 question:
   `"⚠ CLAUDE.md.proposed is <N> lines (ceiling 400, ADR-0136). Something other than an index line is being appended, or the Rules list has accumulated near-duplicates. Check before approving.\n\n"`
   The previous form of this guard warned above 180 and recommended `claude-md-slim`. It fired on
   every run for months because the file was 3,895 lines, and its remedy was measured at 3.0% yield
   on exactly this file and rejected by #380. A warning that always fires and points at a dead
   remedy is noise an operator learns to click past.
5. Transition to `gate_3_project_memory_review`. Display the added lines (`diff CLAUDE.md CLAUDE.md.proposed`, plus the block appended to the archive and the line appended to the index) as text, then present Gate 3 (see §5 Gate 3 block).

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
recommendation is recorded but is NOT authoritative. Do not commit.
As your LAST action, before returning anything, write the completion fact into your OWN worktree:
mkdir -p .claude/dispatch && printf 'tasks=1 files=<M>\n' > .claude/dispatch/tracer-bullet.done
with a literal count for M. The controller measures nothing until that file exists." })
```

<!-- dispatch-site: tracer-bullet-coder class=isolated -->
**Measure nothing until the coder has finished.** Every fact below is read off the filesystem, and
since CC 2.1.232 the `Agent` call above returns before the coder has written anything (issue #435,
ADR-0139). Measured early, `git diff` is smaller than the truth and the budget check returns
`CLEAN` — a false green that no assertion downstream can see, because each assertion measures the
right thing at the wrong moment. Resolve the completion fact first:

<!-- fence-contract: tracer-bullet-completion-gate -->
```bash
# ADR-0133 §D1: quoted heredoc, body runs under bash, `export` carries the caller's values in,
# terminator at COLUMN 0. `project_root` is bound by Step 0; no worktree variable exists at this
# site, so the worktree is found by globbing for the marker's own id — one tracer dispatch per
# chain makes that unambiguous.
export project_root CLAUDE_PLUGIN_ROOT
bash <<'FENCE_BASH'
set -u
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/scripts/dispatch-state.sh" ]; then
  _ds="$CLAUDE_PLUGIN_ROOT/scripts/dispatch-state.sh"
elif [ -f "$HOME/.claude/hooks/dispatch-state.sh" ]; then
  _ds="$HOME/.claude/hooks/dispatch-state.sh"
else
  echo "HALT: dispatch-state.sh not found — the check DID NOT RUN. Run: bash <repo>/staging/sync-to-claude.sh --apply"
  exit 2
fi
[ -n "${project_root:-}" ] || { echo "HALT: project_root is unset"; exit 2; }
_wt=""
for _c in "$project_root"/.claude/worktrees/agent-*; do
  [ -d "$_c" ] || continue
  [ -e "$_c/.claude/dispatch/tracer-bullet.done" ] && { _wt="$_c"; break; }
done
# No worktree carrying the marker is not the same as a worktree carrying a bad one. Ask the helper
# about the project root itself so an inline (non-isolated) build still gets a real token.
[ -n "$_wt" ] || _wt="$project_root"
ST=$(bash "$_ds" "$_wt" tracer-bullet 2>&1); RC=$?
[ "$RC" -eq 3 ] && { echo "HALT: dispatch-state DID NOT RUN — $ST"; exit 2; }
[ "$RC" -eq 2 ] && { echo "HALT: dispatch-state bad invocation — $ST"; exit 2; }
case "${ST%%|*}" in
  DONE) echo "tracer bullet complete: ${ST#*|} — measure now" ;;
  *)    echo "HALT: tracer bullet is ${ST%%|*} — compute NO verdict; leave tracer_bullet_verdict null"; exit 2 ;;
esac
FENCE_BASH
```

On any `HALT`: leave `tracer_bullet_verdict` at `null` and stop. **Do not invent a fourth verdict
value** — the domain is `green|amber|red` and `h16-direction-check.sh`'s amber|red match matches on it; `null` is
already the pre-verdict state and is the honest one for "the probe did not finish". An unfinished
probe is not evidence about the slice, so it must not produce a verdict in either direction.

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

Read `references/step5-implementation.md` when you reach Step 5 — it contains the full Recovery-readiness pre-flight through Fallback dispatch content for this step.

### Step 6 — Review cycle (unconditional skill fallback)

**Dispatch: always the skill fallback (below).** Set `step6_mode: "skill_fallback"` via bash sed
substitution. `hook_verified` governs Step 5's dispatch path only (issue #412, ADR-0164) — it no
longer selects between the two Step 6 paths below.

**Why not the Workflow path (kept below, not deleted — ADR-0129 §D6 precedent for a mechanism whose
unreachability is documented and measured, rather than removed):** Phase 4's re-review runs inside
the same workflow invocation as Phase 3's parallel fix agents, and the orchestrator does not regain
control between the two — there is no turn in which the per-agent worktrees from Phase 3 can be
merged back into the shared checkout before Phase 4 reads it. Phase 4 therefore reviews a checkout
containing none of Phase 3's fixes and reports every Phase 1 finding as still `remaining`, regardless
of what was actually fixed. This is unlike Step 5's Workflow path, where the merge-back runs between
each stage as the orchestrator's own step (`#### Merge-back and base-fork audit`, above) — Step 6
has no analogous per-phase orchestrator turn, because Phases 1-4 are one continuous workflow.
Measured against every manifest under `docs/manifests/`: `step6_mode` is `null` (42) or
`"skill_fallback"` (18) — **never `"workflow"`.** No run has ever taken this path.

#### Workflow dispatch path — Step 6 review cycle (NOT SELECTED — see above, issue #412)

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

#### Skill fallback (the only Step 6 dispatch path — issue #412)

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

### Step 7b — Update the task ledger, and gate on a P1 this feature introduced (ADR-0153)

Runs immediately before Step 7's commit gate. **This is an INSTRUCTION, not an enforcement**
(rule 16). Nothing in the harness executes it; what a green assertion pins is that this text
exists, which is not evidence that a model followed it. It changes the failure shape — a P1 that
this feature introduced becomes visible at the moment somebody can still act on it — and it does
not change the guarantee.

1. Invoke the `project-tasks` skill in its full mode against the project root. It reads the open
   GitHub issues, rescans the markers, and composes a candidate ledger behind its own approval
   gate. It never edits source and never writes before that gate.

2. Then run the gate. `--since` is the date the feature's manifest was created, which is what makes
   "introduced by this feature" answerable at all:

   ```
   bash ~/.claude/skills/project-tasks/scripts/ledger-merge.sh --ledger <root>/TODO.md --p1-gate --since <manifest-created-date>
   ```

   Branch on the exit code. It is a checker; the ids are on stdout.

   - **0** — no open P1. Proceed to Step 7.
   - **5** — only pre-existing P1s. **Report them and proceed.** A gate that blocks every commit on
     a standing debt is a gate people learn to route around, and a routed-around gate protects
     nothing.
   - **1** — at least one P1 opened on or after that date, i.e. introduced while this feature was
     being built. **Stop before the commit gate**, name the ids, and ask whether to fix now or to
     record the decision to defer. Under autopilot, write `needs-human` with the ids and halt: an
     unattended run has nobody to answer the question.
   - **2** or **3** — the gate could not evaluate. An unrun check is not a clean result (rule 4).
     Report the reason and proceed, saying explicitly that the gate did not run.

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
# issue #489/#479, ADR-0158 — the collapse now sees the whole feature. A Step 6 or Gate 5.06
# correction made AFTER the last snapshot lands as a plain tracked modification, never a commit
# (the section below this fence removes the reason the chain ever committed mid-Step-6 at all).
# `git add -u` sweeps it into the same index the reset just rewound: tracked modifications,
# deletions and renames ONLY, the exact scope rule `commit`'s own Step 1 already applies — never
# `git add -A` / `git add .`, which would also stage debris the chain's own worktree escape check
# exists to catch (ADR-0068 §D11). Without this, `commit`'s "already staged" branch treats such a
# correction as merely "not included", and it is dropped from the feature commit silently.
git add -u
_staged_n=$(git diff --name-only --staged | wc -l | tr -d ' ')
echo "COLLAPSED $_n $_b staged=$_staged_n"
exit 0
FENCE_BASH
```

- `COLLAPSED <n> <sha> staged=<k>` → emit `"Step 7: collapsed <n> Step 5 snapshot commit(s) — the
  feature is now one staged diff (<k> file(s) staged)."` and invoke `commit` below. `<k>` is the
  post-`git add -u` total, so it is `>= <n>`'s file count whenever a post-snapshot correction
  existed to sweep in; equal to it otherwise.
- `COLLAPSE_SKIP <reason>` → say which reason and invoke `commit` unchanged. **`foreignCommit` is
  the one worth reading**: the range holds a commit the chain did not make, and folding it away
  would take its message with it.
- exit 3 → report; do not retry, and invoke `commit` unchanged.

**A post-snapshot correction stays uncommitted on purpose (issue #489, ADR-0158).** Step 6 and
Gate 5.06 below make no commit of their own — a controller-side fix, if one is made, is left as a
tracked modification for THIS collapse to sweep up with `git add -u` above. The alternative —
committing it under a `test(...)` or `fix(...)` subject the moment it lands — is what produced
issue #489: `_foreign`'s allowlist covers only the two mechanical snapshot subjects by design (it
must refuse to fold a commit it cannot attribute), so any other subject aborts the whole collapse
and the feature stays scattered. Removing the commit removes the cause; the guard above is
unchanged and untouched.

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

**Step 7.0b bumps this chain's own baseline rows (issue #460, ADR-0166).** The archive above is the
event that enrols this chain's SPEC into the frozen corpus baseline, so this is where its rows are
written; the rows must land in **this** commit or the next unrelated author inherits the red.

<!-- fence-contract: c2c-step7-baseline-bump -->
```bash
# ADR-0133 §D1 (issue #394): everything between the two FENCE_BASH lines runs under BASH, not under
# the host shell, which is zsh here and differs from bash on word splitting, unmatched globs and
# `echo` escapes. `export` forwards this body's caller-bound free variables across the new process
# boundary; a plain shell variable does not survive it. Terminator at COLUMN 0; an indented one is
# swallowed into the here-document and destroys this fence's exit code silently.
export ARCHIVED_SPEC PLAN ROOT CLAUDE_PLUGIN_ROOT
bash <<'FENCE_BASH'
# Free variables, bound by the orchestrator before this block runs:
#   ARCHIVED_SPEC   the path spec-archive.sh reported above (ARCHIVED or ALREADY)
#   PLAN            manifest.artifacts.plan
#   ROOT            <project-root>
# Two-tier resolution, copied from the Requirement-ID coverage gate above, which resolves the
# sibling spec-coverage.sh the same way.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] \
   && [ -f "$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh" ]; then
  _rows="$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh"
elif [ -f "$HOME/.claude/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh" ]; then
  _rows="$HOME/.claude/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh"
else
  echo "BASELINE_BUMP_NORUN noScript"
  echo "  spec-coverage-baseline-rows.sh is not deployed. Run: bash <repo>/staging/sync-to-claude.sh --apply"
  exit 3
fi
_baseline="$ROOT/staging/plugin/scripts/tests/spec-coverage-scope-baseline.tsv"
# --tests-root is passed UNCONDITIONALLY, unlike the Gate 4.x call above which omits it when
# manifest.test_cmd_placeholder or manifest.test_cmd_provisional is true (ADR-0166 §D5): the
# baseline's rows are defined by what the harness computes, and the harness always passes it.
_out=$(bash "$_rows" --bump --baseline "$_baseline" --spec "$ARCHIVED_SPEC" --plan "$PLAN" --tests-root "$ROOT")
_rc=$?
printf '%s\n' "$_out"
exit "$_rc"
FENCE_BASH
```

- `0` with `BUMP-NOOP: …` → proceed silently. Nothing was written.
- `0` with `BUMPED <n> row(s)` → the baseline is modified on disk. Emit one line naming the path and
  the count, and **add that path to the `--include` list of the `commit` invocation below**.
- non-zero (`1` conflict, `2` invalid, `3` did not run) → **HALT. Do not invoke `commit`.** Print the
  script's stderr verbatim and name the file a human must look at. This is deliberate: an unbumpable
  baseline stops the chain that would have caused the drift, at the point someone can still act on it.

The halt above and the `--include` extension below are **instructions, not enforcements** (rule 16):
what is enforced is this fence's own exit code, executed by `spec-coverage-baseline-bump.test.sh`.

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
Arguments: --include <archived-spec-path>,<manifest-path>[,<baseline-path> — only when the bump reported BUMPED]
```

The skill manages the HITL gate (AskUserQuestion), Conventional Commits message generation, and the PR option internally. The orchestrator does nothing after invocation: the skill closes the cycle on its own.

**Step 7.1 — classify what `commit` did (issue #410, ADR-0135 §D3).**

The verdict is read off the manifest on disk, never off the skill's own report: `commit` emits no
machine-readable outcome, and an agent's self-report is not a gate (ADR-0047 §A3). "Nothing to
commit" and "declined" are told apart the same way — not by asking what happened, but by whether
the manifest is committed.

The classification itself is extracted into a standalone script, `commit-outcome-check.sh`, the
single definition shared with the `commit-outcome-backstop` `PostToolUse` hook (ADR-0168 §D1 —
that hook is added by a later task, this fence is just its other caller).

<!-- fence-contract: c2c-step7-commit-outcome -->
```bash
# ADR-0133 §D1 (issue #394): the body between the two FENCE_BASH lines runs under BASH, not under
# the host shell. `export` forwards CLAUDE_PLUGIN_ROOT, this body's only caller-bound free
# variable, across the new process boundary; a plain shell variable does not survive it. Terminator
# at COLUMN 0; an indented one is swallowed into the here-document and destroys this fence's exit
# code silently, and this fence's whole contract is its exit code (ADR-0135 §D3).
export CLAUDE_PLUGIN_ROOT
bash <<'FENCE_BASH'
# Two-tier resolution, copied from the Requirement-ID coverage gate above, which resolves the
# sibling spec-coverage.sh the same way. The classification itself lives only in
# commit-outcome-check.sh (ADR-0168 §D1, §D3) — no inline fallback copy.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] \
   && [ -f "$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/commit-outcome-check.sh" ]; then
  _check="$CLAUDE_PLUGIN_ROOT/skills/concept-to-code/scripts/commit-outcome-check.sh"
elif [ -f "$HOME/.claude/skills/concept-to-code/scripts/commit-outcome-check.sh" ]; then
  _check="$HOME/.claude/skills/concept-to-code/scripts/commit-outcome-check.sh"
else
  echo "COMMIT_OUTCOME_NORUN noScript"
  echo "  commit-outcome-check.sh is not deployed. Run: bash <repo>/staging/sync-to-claude.sh --apply"
  exit 3
fi
bash "$_check" "<manifest-path>"
exit $?
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
- `MACOS_DETECTED` → transition `gate_h1b_brainstorm → gate_h1c_macos_ux`, show **Gate H1c** (see below). After Gate H1c resolves, transition `gate_h1c_macos_ux → gate_h1d_claude_design`.
- `NOT_MACOS` → transition `gate_h1b_brainstorm → gate_h1d_claude_design` directly. No Gate H1c shown.

#### Gate H1c — macOS UX design (optional, conditional)

Identical to standard Gate 1c (see §5 Gate 1c block). On `[y]`: invoke `macos-ux` design, write UX-BLUEPRINT.md, set `artifacts.ux_blueprint`, transition `gate_h1c_macos_ux → gate_h1d_claude_design`. On `[n]`: transition directly.

**CRITICAL — chain continuation (no stop):** After macos-ux returns, do NOT produce any text and do NOT wait. Set artifact, transition, proceed to Gate H1d.

**[Autopilot default: "No". Emit: "Gate H1c: autopilot — skip macOS UX ✓"]**

#### Gate H1d — Claude Design decision (optional, VCS-052/ADR-0181)

Identical to standard Gate 1d (see §5 Gate 1d block), including its two-phase 1d-A/1d-B structure
and its "Not yet, still designing" resumable pause. On 1d-A `[y]`: invoke `claude-design-brief`,
write DESIGN-PROMPT.md, set `artifacts.design_prompt`; do not transition; present 1d-B. On 1d-B
paste: run `design-url-check.sh`, write DESIGN.md, set `artifacts.design`, transition
`gate_h1d_claude_design → step_h2_plan`. On 1d-A `[n]` or 1d-B "Skip after all": transition
`gate_h1d_claude_design → step_h2_plan` directly, `artifacts.design`/`artifacts.design_prompt`
stay null (whichever was never set). On 1d-B "Not yet": do not transition; `current_step` stays
`gate_h1d_claude_design`, resumable.

**CRITICAL — chain continuation (no stop):** After claude-design-brief returns, or after a pasted
URL is checked, do NOT produce a closing/handoff sentence. Set artifact(s), transition (or not, on
"Not yet"), proceed to Step H2 once `gate_h1d_claude_design → step_h2_plan` actually fires.

**[Autopilot default: "No". Emit: "Gate H1d: autopilot — Claude Design needs a human in a browser, skipped ✓"]**

#### Step H2 — Plan (EnterPlanMode)

1. Emit: "Hybrid path — entering plan mode with SPEC context..."
2. Call `EnterPlanMode`.
3. Read SPEC.md (and BRAINSTORM.md, DESIGN.md if present) plus relevant project files.
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

Read `references/hitl-gates.md` when you reach a gate — it contains the full Gate 0 through Gate 5.6 content for this section.

## 6. Coexistence invariants

This skill DOES NOT modify any of the following. They remain active and orthogonal:

- `~/.claude/agents/coder.md` — Pre-flight Pattern Classifier (ADR-0001) fires in Step 5 by default.
- `~/.claude/agents/reviewer.md` — Pattern-drift check (ADR-0001) fires implicitly in Step 6 review cycle.
- `~/.claude/agents/refactorer.md` — Snapshot Harness Integration (ADR-0002) is orthogonal (refactorer not dispatched by this skill).
- `~/.claude/agents/architect.md` — carries native persistent memory (`memory: project`, VCS-056/ADR-0183): a `.claude/agent-memory/architect/` directory, auto-injected at dispatch start, replacing the retired ADR-0012 inject/harvest mechanism. This skill does not edit architect.md at runtime.
- `~/.claude/skills/review-triage-fix/SKILL.md` — v1.2 Add+Remove rule invoked as-is in Step 6; `reviewer`/`debugger` (dispatched by it, not by this skill) both carry native persistent memory (VCS-055/ADR-0182, VCS-056/ADR-0183) rather than the retired ADR-0012 contract.
- `~/.claude/skills/interview-driver/SKILL.md` — invoked as-is in Step 1 (greenfield only).
- `~/.claude/skills/claude-md-generator/SKILL.md` — invoked as-is in Step 3 (additive directive conveyed in the prompt template, not in claude-md-generator's SKILL.md).
- `~/.claude/skills/design-brainstorm/SKILL.md` — invoked at gate 1b (`[y]`). Writes only `BRAINSTORM.md`; this skill updates `artifacts.brainstorm` in the manifest.
- `~/.claude/skills/macos-ux/SKILL.md` — invoked at gate 1c / gate H1c (`[y]`), conditional on macOS/SwiftUI SPEC detection. Writes only `UX-BLUEPRINT.md`; this skill updates `artifacts.ux_blueprint` in the manifest. Design mode only in chain; review mode is standalone.
- `~/.claude/skills/claude-design-brief/SKILL.md` — invoked at gate 1d / gate H1d (`[y]`), unconditional and optional (VCS-052, ADR-0181). Writes only `DESIGN-PROMPT.md`; this skill updates `artifacts.design_prompt` in the manifest. It never writes `DESIGN.md` — that file is written by this skill (concept-to-code), from the human's pasted shared URL, at gate 1d-B / H1d-B.
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
