# ADR-0010 — web-e2e-test (live web E2E testing via Chrome MCP)

**Status:** Proposed — 2026-05-22

**Deciders:** architect (dispatch orchestrator), Stefano Ferri (final approval)

**Related:** ADR-0003 (concept-to-code chain — the chain where the gate is inserted),
ADR-0008 (workflow v2 brainstorm — precedent of optional gate + non-terminal skill invoked
by the chain), ADR-0005 (vibe-status — standalone skill with report), ADR-0007
(concept-to-code e2e-smoke — precedent for chain smoke-testing), ADR-0002/0009 (pattern
"harness structural anchor" and "dialogic/orchestrating skill not end-to-end testable").

---

## Context

Repeatedly an operational gap has emerged: **agents do not test the UI**. After implementing
a frontend feature (Step 5 of the concept-to-code chain, or a direct fix), a "manual UI
check" remains at the user's charge — e.g. the SwiftUI wizard of rempay. The chain closes on
"unit tests pass", not on "the code is live and works in the browser".

Claude Code now has `claude-in-chrome` tools (browser automation beta): the agent can navigate
a real browser, take screenshots, read the console, monitor network requests, click and fill
forms, record GIFs. For **web projects** this allows closing the gap: exercising the golden-path
flows of the just-implemented feature **end-to-end on live code** and producing an E2E report
(screenshots + console errors + network failures + per-flow outcome).

This ADR designs the `web-e2e-test` capability: form (skill/gate), web-detection, server
lifecycle, report contract, failure handling, anti-rabbit-hole guardrails, and testability of
the feature itself.

**Explicit scope:** the feature applies **only to web projects**. For SwiftUI/macOS/native/
CLI/libraries it does NOT apply and MUST NOT activate (no false starts on rempay or a CLI).
Manual verification remains for non-web.

**Verified facts (`code.claude.com/docs/en/chrome`, 2026-05-22):**

- Browser tools are enabled with `claude --chrome` or `/chrome` in session; they are **deferred**
  (increase context, to load via `/mcp claude-in-chrome` or ToolSearch when needed).
- localhost is a documented primary use case ("navigate to your local server").
- On login/CAPTCHA "Claude pauses and asks you to handle it manually".
- **JavaScript dialogs (alert/confirm/prompt) block browser events** and prevent Claude from
  receiving commands; they must be dismissed manually ("Dismiss the dialog manually, then tell
  Claude to continue").
- The **extension service worker goes idle** in long sessions -> connection drops ("Reconnect
  extension"). Typical errors: "No tab available", "Receiving end does not exist".
- Per-site permissions are inherited from the Chrome extension (managed there).

**Explicit assumptions (NOT validated — the feature rests on these):**

- **`claude-in-chrome` tools are available to the ORCHESTRATOR, NOT to sub-agents.** Official
  docs say sub-agents inherit the thread's tools, **but** in practice this is a known recurring
  bug (anthropics/claude-code issues #7296, #13605, #13898, #34935): sub-agents launched via
  Task tool do **not** reliably access MCP tools and tend to hallucinate plausible results. For
  an E2E test a hallucinated result is the worst failure (false green). **Conservative decision:**
  the feature is guided by the **orchestrator**, never delegated to a sub-agent. (Consistent with
  blueprint §2 constraint: sub-agents do not spawn sub-agents; here additionally they lack
  browser tools.)
- The `SPEC.md` of a greenfield project has a "success criteria"/"Definition of Done" section
  from which golden-path flows can be derived (verified on the system's interview-driver template;
  assumed for external projects).
- No user convention currently exists for declaring E2E flows or the dev server URL. The proposed
  `.claude/web-e2e.yaml` contract is a **new convention** introduced by this ADR (optional;
  see D2/D4).
- The repo `vibe-coding-system` is NON-git: the deliverables are the 3 markdowns; the deploy of
  the live artifacts (`~/.claude/skills/web-e2e-test/`, gate in the chain) is a separate task
  (TDD plan), without commit step.

---

## Decision

Introduce **a standalone `web-e2e-test` skill**, callable on demand, **reused by a new optional
"Gate 6 — E2E web" in the concept-to-code chain** (after Gate 5 review). The skill instructs
the **orchestrator** to: (1) verify the project is web and auto-skip otherwise; (2) discover/wait
for the dev server; (3) load `claude-in-chrome` tools; (4) exercise the golden-path flows
(declared or derived from the SPEC, with user confirmation); (5) produce a report
`docs/e2e/<date>-<topic>.md` with screenshots + console errors + network failures + per-flow
outcome; (6) apply anti-rabbit-hole guardrails (timeout, max-retries, stop-and-ask). Manifest
schema **1.2** (retrocompat 1.0/1.1) with new field `artifacts.e2e`. Skill harness =
**structural anchor** on the SKILL.md (the feature pilots a real browser -> not deterministically
testable headless; honest as design-brainstorm/ADR-0009).

Below is the decision for each of the 8 architectural questions.

### D1 — Form: standalone skill + reusing gate (both)

**Standalone skill `web-e2e-test`** callable on demand, **reused** by an optional gate in the
chain (`Gate 6 — E2E web`, after Gate 5). Not a gate-only, not a skill-only.

Rationale:
- **Standalone** because the "manual UI check" gap also presents itself outside the chain (direct
  fix, brownfield without chain, iteration on existing feature). A callable skill covers all cases.
- **Reusing gate** because inside the chain the natural moment for E2E is right after review
  (Gate 5): code implemented + (optionally) reviewed -> verify live. The gate does not duplicate
  the logic: it **invokes the same skill** (same pattern as Gate 1b, which invokes
  `design-brainstorm`; and Step 6, which invokes `review-triage-fix`). Single source of truth.
- **Optional and auto-skip:** the gate appears only if the project is web (D2). On non-web
  projects the gate is a silent no-op (chain UX unchanged for rempay/CLI).

**Subject = orchestrator.** The skill instructs the orchestrator (main CLI agent), which is the
only one with `claude-in-chrome` tools (see assumption in Context). The skill does NOT dispatch
a sub-agent for the browser part. Consistent with concept-to-code §6 ("this skill instructs the
orchestrator").

### D2 — Web-detection: cascade of signals, fail-safe towards NON-web

The skill classifies the project as web via a **cascade of signals** evaluated on the
`project_root` (ascending from `cwd`), in order; the first that decides wins:

1. **Explicit override (highest priority):** file `.claude/web-e2e.yaml` present ->
   `web: true` implicit (the user configured it on purpose). If the file has `web: false` ->
   explicit NON-web, skip.
2. **`package.json` with known dev server:** `package.json` exists and contains a script
   `dev`/`start`/`serve` **or** a dependency among `vite`, `next`, `react-scripts`,
   `@angular/cli`, `vue`, `svelte`, `astro`, `nuxt`, `remix`, `webpack-dev-server` ->
   `web: true`.
3. **Static web:** an `index.html` exists at root or in `public/`/`src/`/`dist/` ->
   `web: true` (servable static site).
4. **No signal -> `web: false`:** the feature **does NOT activate**. If invoked standalone
   on a non-web project, the skill declares it ("non-web project detected, web-e2e-test not
   applicable") and terminates without error. In the chain, Gate 6 is a silent no-op.

**Anti-false-positive on rempay/native:** a SwiftUI/macOS project has no `package.json` with
dev server or `index.html` -> falls to (4) -> skip. A Python CLI (e.g. pricing-markup-cli)
likewise. A library likewise. The default is "non-web" — the feature activates only on a
positive signal, never on absence of signal.

### D3 — Server lifecycle: prefer-running, opt-in auto-start, readiness polling

**Default: prefer-running (the user starts the server).** The skill first **tries to connect**
to a candidate URL; only if none responds and the user authorizes it, it tries to start it.

**URL discovery** (in order):
1. `.claude/web-e2e.yaml` field `base_url` (e.g. `http://localhost:5173`) -> authoritative.
2. Known candidate ports for stack: vite `5173`, next/react-scripts `3000`, vue-cli `8080`,
   angular `4200`, astro `4321`, generic `8000`/`8888`. HTTP probe (HEAD/GET) on
   `http://localhost:<port>` until one responds.
3. If none responds -> **stop-and-ask**: asks the user for the URL or authorization to start
   the server.

**Server start (opt-in, never silent):** if no URL responds, the skill **asks for confirmation**
before launching the dev server (HITL — a process start is a side effect). The start command
comes from `.claude/web-e2e.yaml` field `start_cmd` (e.g. `npm run dev`) or is proposed by the
orchestrator and confirmed by the user. Launched in background (`run_in_background`).

**Readiness check:** HTTP polling on `base_url` with backoff (e.g. every 1s, max ~30s /
`startup_timeout_s` configurable). "Ready" = HTTP response < 500 (even 401/302 counts as
"server up"). Timeout -> stop-and-ask (does not proceed blindly).

**Teardown:** if **the skill started** the server, it **stops it at the end** (kill background
process) and notes it in the report. If the server was **already running** (prefer-running), the
skill **does NOT stop it** (not its property — principle of least surprise).

### D4 — What it tests: declared flows > derived-with-confirmation (never blind auto-generation)

Golden-path flows come from, in order of preference:

1. **Declared by the user:** `.claude/web-e2e.yaml` field `flows:` (list of flows with
   `name`, `steps` in natural language, and optional `expect`). Maximum reliability: the
   contract is explicit, reproducible, versionable.
2. **Derived from SPEC/plan, WITH user confirmation:** if there is no `web-e2e.yaml`, the skill
   **proposes** a draft of flows extracted from the "success criteria"/"Definition of Done" of the
   `SPEC.md` (or from the plan, in the chain) and **shows them to the user for confirmation/
   modification** before executing them (`AskUserQuestion`). Does NOT execute auto-generated
   flows without confirmation.
3. **Ad-hoc session checklist:** in standalone, the user can dictate flows in the prompt; the
   skill structures and confirms them.

**Automation vs reliability trade-off (explicit):** auto-generating steps (selectors, clicks)
from the SPEC alone is unreliable — the SPEC describes *what* in natural language, not *which
DOM selectors*. The skill therefore works at the level of **intent** ("fill the login form with
invalid data and verify the error appears"), leaving the orchestrator+browser to translate into
concrete actions at runtime (the documented usage model of claude-in-chrome: natural language
instructions, not Playwright scripts). Selectors are NOT hardcoded in the skill (they would be
fragile and stack-specific): the flow remains declared as intent, execution is adaptive. This
maximizes robustness at the cost of non-determinism (mitigated by D6/D7).

### D5 — Output: markdown report `docs/e2e/<date>-<topic>.md` + manifest `artifacts.e2e`

The skill writes **a single report**: `<project-root>/docs/e2e/YYYY-MM-DD-<topic-slug>.md`
(creates `docs/e2e/` if absent). Screenshots are saved alongside, in
`docs/e2e/assets/YYYY-MM-DD-<topic-slug>/` and referenced in markdown with relative paths.

Report structure (English template, Italian prose — consistent with SPEC/ARCH/ADR):
- **Header:** date, topic, base_url, server mode (already-running | started-by-skill),
  flow source (yaml | derived-confirmed | ad-hoc), overall outcome (PASS | PARTIAL | FAIL).
- **Per flow:** name, steps executed, outcome (`pass` | `fail` | `blocked`), attached
  screenshot (at least 1: final state or failure point), console errors detected (filtered
  for error/warning patterns, not the entire dump — doc guide), network failures (status >= 400
  or failed requests).
- **Failure classification (D6):** each failure marked `feature-bug` (real app error) |
  `test-fragile` (selector/flow no longer valid) | `infra` (server down, blocking dialog,
  lost connection) | `unknown`.
- **Open questions / residual manual verification:** what the skill could NOT verify
  (login/CAPTCHA, flows requiring external state).

**Manifest integration:** new field `artifacts.e2e` (path to the report) in manifest schema
**1.2** (retrocompat 1.0/1.1: optional field, default null; 1.0/1.1 manifests remain valid).
The chain populates `artifacts.e2e` after Gate 6. The standalone skill does NOT touch any
manifest (like design-brainstorm writes only BRAINSTORM.md).

### D6 — Failure handling: continue-and-collect + classification + stop-and-ask on blocks

**Default: continue and collect all flow failures** (does not stop on first failure). An E2E
report has value precisely if it lists *all* broken flows, not just the first. Exception:
**infrastructural blocks** (server down, blocking JS dialog, lost browser connection) stop
execution (stop-and-ask) — D7.

**Classification of each failure** (heuristic, declared in report):
- **`feature-bug`:** the element exists and responds, but the observed behavior contradicts the
  flow's `expect` (e.g. submit with invalid data -> no error message), or the console shows an
  application error (JS exception, 500 on backend).
- **`test-fragile`:** the expected element is not found / the flow can no longer be mapped to
  the current UI (changed selector/label). NOT necessarily a feature bug: often the declared
  flow is stale. Marked distinctly to avoid crying "bug" in vain.
- **`infra`:** server not reachable, blocking dialog, "Receiving end does not exist", "No tab
  available". Not a bug or fragile test: it is environment.
- **`unknown`:** not classifiable with certainty -> flagged for human review.

**HITL on failures:** the skill does NOT fix the code (not its role: it is verification, not
fix). At the end of the run it presents the summary and, if there are `feature-bug` entries,
**recommends** a `review-triage-fix` cycle or a `debugger` dispatch (user's decision). In the
chain, a FAIL/PARTIAL outcome at Gate 6 does NOT block completion but is highlighted in the
final report.

### D7 — Anti-rabbit-hole: per-action timeout, max-retries, stop-and-ask after N, no-dialog

Incorporates the system prompt guide ("Avoid rabbit holes") and doc facts on dialog/idle:

- **`tabs_context` at startup:** before acting, the skill instructs the orchestrator to read
  the tab context (which pages are available) to avoid exploring blindly (doc guide: "use a
  file to discover all available pages before exploring further").
- **Per-action timeout:** every browser action (navigate, click, wait for element) has a budget
  (default ~10s / `action_timeout_s`). Expired -> mark the step `blocked`, do not retry in loop.
- **Max-retries per element:** an element not found/unresponsive -> at most **2 retries** (e.g.
  after a brief wait for async rendering), then `test-fragile`/`blocked`. Never an infinite loop
  on the same element.
- **Stop-and-ask after N infra blocks:** after **2** infrastructural blocks (dialog, lost
  connection, server down) the skill **stops and asks the user** instead of insisting. Consistent
  with the fact that JS dialogs and service-worker-idle require manual intervention.
- **No-dialog discipline:** the skill does NOT attempt to force blocking JS dialogs (the doc says
  they block events and must be dismissed manually); if it detects a block -> stop-and-ask.
- **Login/CAPTCHA:** not automated (the doc says Claude pauses and asks). The skill marks them
  as "residual manual verification" in the report and continues with flows that don't require them.
- **Global session budget:** an overall wall-clock cap (`session_timeout_s`, default ~5 min)
  beyond which the skill closes and writes a partial report, to avoid burning context/time.

### D8 — Harness/testability: structural anchor on SKILL.md + web-detection smoke (no real browser)

A feature that pilots a real browser **is not deterministically testable headless**: there is no
browser, no dev server, no UI in the CI harness. Honesty as in design-brainstorm (ADR-0008) and
as with the `ask` gate of ADR-0009 (the payload is tested, not the rendering).

**What the harness verifies (deterministic, headless):**
1. **Structural anchor on SKILL.md** (`tests/run-tests.sh`, bash 3.2-clean, `ok`/`bad`,
   `PASS=N FAIL=0`): presence of `name: web-e2e-test`, absence of
   `disable-model-invocation: true` (must be invocable from the gate), presence of contract
   sections (web-detection, server lifecycle, anti-rabbit-hole, report contract, `## Language`,
   use of `tabs_context`, "orchestrator-only").
2. **Smoke of web-detection logic** (the only *pure* and testable piece): if the skill includes
   a helper script `detect-web.sh` (plan decision), the harness exercises it on `mktemp -d`
   fixtures — `package.json` with `vite` -> `web`; SwiftUI fixture (only `.swift` +
   `Package.swift`) -> `non-web`; CLI fixture -> `non-web`; `index.html` -> `web`;
   `.claude/web-e2e.yaml` with `web:false` -> `non-web`. This is deterministic and protects the
   HARD constraint "no false starts on non-web".
3. **Anchor in the chain harness** (concept-to-code): verifies that Gate 6 is registered in the
   chain's SKILL.md (literal `Gate 6` / `web-e2e`) and that the manifest schema cites
   `artifacts.e2e` / `1.2`.

**What is NOT verifiable by the harness (remains open question, validatable only in real use):**
- The browser end-to-end execution (real navigate/click/screenshot).
- Dev server readiness, teardown, console/network capture.
- The feature-bug vs test-fragile classification on a real UI.
- The actual anti-rabbit-hole behavior (real timeouts/retries).

These remain validatable **only in a pilot** with a real web project. The plan report must
declare this explicitly (as for the `ask` gate of ADR-0009).

---

## `.claude/web-e2e.yaml` Contract (new convention, optional)

Introduced by this ADR. All fields optional; in their absence, the skill falls back to the
D2/D3/D4 defaults. Schema:

```yaml
# .claude/web-e2e.yaml — optional; configures web-e2e-test for this project
web: true                       # explicit web/non-web override (default: D2 cascade)
base_url: http://localhost:5173 # dev server URL (default: probe known ports D3)
start_cmd: npm run dev          # start command (used only if no server responds, opt-in)
startup_timeout_s: 30           # readiness polling cap
action_timeout_s: 10            # timeout per browser action
session_timeout_s: 300          # global session budget
flows:                          # declared golden-path flows (preferred over derived)
  - name: login-invalid
    steps:
      - "go to /login"
      - "fill email with 'x' and empty password, press Login"
    expect: "a validation error message appears"
  - name: dashboard-loads
    steps:
      - "go to / as authenticated user"
    expect: "dashboard loads without console errors"
```

---

## Alternatives considered (for each of the 8 questions)

### D1 — Form

- **Gate-only in the chain (no standalone skill):** rejected. The "manual UI check" gap also
  presents itself outside the chain (direct fixes, brownfield, iteration). A gate-only would
  leave all non-chain cases uncovered.
- **Standalone skill only (no gate):** rejected. Inside the chain, the E2E after review is the
  natural moment; leaving it to the user to invoke manually would break the continuity
  "concept->code->verified" that the chain promises.
- **Dedicated sub-agent `e2e-tester`:** rejected. Task-launched sub-agents do not reliably have
  MCP browser tools (documented issues): an e2e-tester sub-agent would hallucinate results (false
  green) — the worst failure for a test. The capability MUST run on the orchestrator.

### D2 — Web-detection

- **Mandatory explicit config (`web-e2e.yaml` always required):** rejected. Too much friction;
  the feature would never activate on web projects not yet configured, defeating the intelligent
  auto-skip in the chain.
- **Detection only via `package.json`:** rejected. Excludes static sites (`index.html` served)
  and projects with non-Node dev server. The cascade covers more cases.
- **Activate by default and deactivate on non-web (denylist):** rejected. Inverts the fail-safe:
  would risk false starts on native/CLI for absence of a marker. The default MUST be "non-web";
  activation only on a positive signal.

### D3 — Server lifecycle

- **Always auto-start (skill always starts the server):** rejected. A process start is a side
  effect; if the server is already up, duplicating it causes port conflicts. Prefer-running +
  opt-in start is less surprising.
- **Never start (always requires pre-running server):** rejected. Unnecessary friction when the
  user wants the full end-to-end check; opt-in start with confirmation is the compromise.
- **Fixed sleep for readiness:** rejected. Fragile (slow server -> false "not ready"; fast server
  -> wasted time). Polling with timeout is robust.

### D4 — What it tests

- **Blind auto-generation of flows from SPEC (no confirmation):** rejected. The SPEC describes
  intent in natural language, not selectors; executing auto-generated flows without confirmation
  produces fragile tests and false failures. User confirmation is the reliability gate.
- **Only declared flows in YAML (no derivation):** rejected as the sole path. Too much friction
  for the first run; derivation-with-confirmation lowers the entry barrier.
- **DOM selectors hardcoded in the skill:** rejected. Stack-specific and fragile; the skill works
  at the intent level and leaves execution adaptive to the browser (documented usage model of
  claude-in-chrome).

### D5 — Output

- **Chat output only (no file):** rejected. An E2E report with screenshots must be persisted for
  audit/sharing and for chain manifest integration.
- **Report inside the manifest itself:** rejected. The manifest is a state machine, not a document;
  screenshots do not fit. The manifest points to the report (`artifacts.e2e`).
- **Manifest schema without new version (reuse 1.1):** rejected. Adding a semantically new field
  (`artifacts.e2e`) merits the bump to 1.2 for validation clarity, maintaining retrocompat
  (optional field, 1.0/1.1 remain valid). Consistent with the 1.0->1.1 precedent of ADR-0008.

### D6 — Failure handling

- **Stop on first failure (fail-fast):** rejected. A report listing only one broken flow forces
  multiple re-runs; collecting all flow failures provides more value at once. (Exception: infra
  blocks stop anyway — D7.)
- **The skill fixes the code (auto-fix):** rejected. Violates the verification/fix separation; a
  test that self-corrects masks the bug and can introduce regressions. The skill verifies and
  recommends; the fix is for `review-triage-fix`/`debugger`/coder, on user decision.
- **Do not distinguish feature-bug from test-fragile:** rejected. Would collapse false positives
  (changed selector) into "feature bug", eroding trust in the report. Classification is the key
  discriminator.

### D7 — Anti-rabbit-hole

- **No timeout / unlimited retries:** rejected. This is exactly the rabbit-hole the system prompt
  guide warns against; an unresponsive element would block the session.
- **Attempt to dismiss JS dialogs via script:** rejected. The doc says dialogs block events and
  must be dismissed manually; attempting to force them is unreliable and risks loops. Stop-and-ask
  is the documented approach.
- **Automate login/CAPTCHA:** rejected. The doc says Claude pauses and asks; attempting to
  automate them violates the extension design and site permissions.

### D8 — Harness/testability

- **End-to-end harness with real headless browser (Playwright in CI):** rejected. Introduces a
  heavy stack (Node + Playwright + browser), stack-locked, against the bash 3.2-clean / zero-dep
  constraint of the system, and in any case would not test the real `claude-in-chrome` tools
  (which require the extension + Claude Code session). The value does not justify the cost.
- **No harness (feature not testable -> no tests):** rejected. The web-detection part is pure and
  MUST be tested (protects the HARD constraint "no false starts on non-web"). The structural anchor
  + web-detection smoke is the maximum honestly testable.
- **Mock the entire browser session:** rejected. A browser mock tests the mock, not the feature;
  it gives false security. Better to honestly declare what remains validatable only in a pilot.

---

## Consequences

### Positive

- Closes the loop "the code is live and works in the browser", not just "unit tests pass".
  Fills the "manual UI check" gap for web projects.
- **Clean reuse:** Gate 6 invokes the same standalone skill (single source of truth, pattern
  already proven by Gate 1b->design-brainstorm and Step 6->review-triage-fix).
- **Auto-skip on non-web:** no false starts on rempay (SwiftUI) / CLI / libraries. The default
  fail-safe is "non-web".
- **Persistent report** with screenshots + console + network + per-flow outcome, integrated in
  the manifest (`artifacts.e2e`), useful for audit and for deciding a fix cycle.
- **Feature-bug vs test-fragile classification** preserves trust in the report (a changed selector
  is not cried as a bug).
- **Explicit anti-rabbit-hole** (timeout, max-retry, stop-and-ask, no-dialog) consistent with
  the system prompt guide and doc facts on dialog/idle.

### Negative

- **Intrinsic non-determinism:** intent-level flows executed on a real UI are not 100%
  reproducible. Mitigated by YAML-declared flows (more stable) and failure classification, but
  it remains a feature characteristic.
- **Browser tool fragility:** idle service worker, blocking dialogs, lost connection,
  login/CAPTCHA. Mitigated by stop-and-ask and "infra"/"manual verification" marking, but can
  still interrupt a run.
- **Dependency on an unvalidated assumption** (browser tools orchestrator-only): if in the future
  sub-agents reliably inherited MCP tools, the choice would remain valid (orchestrator works
  anyway) but sub-optimal (lost parallelization). Documented as open question.
- **Limited testability:** most of the feature is validatable only in a pilot. The harness covers
  only web-detection + structural anchor. Known limitation, annotated (as ADR-0008/0009).
- **Setup required:** the user must have the Claude in Chrome extension installed and `--chrome`
  active; without it, the skill cannot execute (must detect this and degrade to "prerequisites
  missing", not fake a run).

### Neutral

- **Manifest schema 1.2:** new optional field `artifacts.e2e`; 1.0/1.1 remain valid
  (retrocompat). `manifest-validate.sh` must be extended to accept 1.2 (plan).
- **New convention `.claude/web-e2e.yaml`** introduced by this ADR; optional, should be
  documented in a target project's CLAUDE.md.
- **MCP tools deferred:** browser tools increase context if "enabled by default"; the skill loads
  them on-demand (via `/mcp claude-in-chrome` / ToolSearch) only when the project is web and the
  flows are confirmed — not on every session.
- Repo `vibe-coding-system` NON-git: the deliverables are the 3 markdowns; the deploy of the live
  artifacts (`~/.claude/skills/web-e2e-test/`, chain patch) is a separate task (TDD plan), without
  commit step.

---

## References

- ADR-0003 — `docs/architecture/ADR-0003-concept-to-code-chain.md` (chain where Gate 6 is
  inserted; manifest YAML + HITL gate pattern)
- ADR-0008 — `docs/architecture/ADR-0008-concept-to-code-workflow-v2-brainstorm.md` (precedent
  of optional gate + non-terminal skill invoked by the chain; schema 1.0->1.1; honest structural
  anchor harness on dialogic skill)
- ADR-0005 — `docs/architecture/ADR-0005-vibe-status-skill.md` (standalone skill with report)
- ADR-0007 — `docs/architecture/ADR-0007-concept-to-code-e2e-smoke.md` (chain smoke-test)
- ADR-0009 — `docs/architecture/ADR-0009-db-backup-guardrail.md` (separation "testable payload"
  vs "runtime behavior validatable only in pilot"; doc-gap -> fail-safe)
- `~/.claude/skills/concept-to-code/SKILL.md` (state machine; gate->skill reuse pattern)
- `~/.claude/skills/design-brainstorm/SKILL.md` (skill invoked by the chain, writes only its
  own artifact; structural-anchor harness)
- Chrome integration: `code.claude.com/docs/en/chrome` (verified 2026-05-22: localhost,
  login/CAPTCHA pause, blocking JS dialogs, service-worker idle, inherited site permissions,
  deferred tools via `/mcp claude-in-chrome`)
- Sub-agent + MCP: `code.claude.com/docs/en/sub-agents` (documented inheritance) +
  anthropics/claude-code issues #7296/#13605/#13898/#34935 (**verified gap:** Task-launched
  sub-agents do not reliably access MCP tools -> browser tools orchestrator-only)
- `feedback_bash32-constraint` (bash 3.2-clean harness)
