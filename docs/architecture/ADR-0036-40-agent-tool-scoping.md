# ADR-0036 — Agent tool scoping per blueprint section 3

**Status:** Accepted
**Date:** 2026-07-11
**Author:** istefox
**Supersedes:** none
**Amends:** none
**Related:**

- SPEC: `docs/specs/40-agent-tool-scoping-per-blueprint-section.spec.md` (= `SPEC.md` at repo root,
  GitHub issue #40, confirmed byte-identical by diff before writing this ADR)
- Manifest: `docs/manifests/2026-07-11-40-agent-tool-scoping.manifest.yml` (`current_step:
  step_2_architecture`, `autopilot: true`) — not edited by this ADR; artifact paths are the
  orchestrator's responsibility to record post-dispatch (ADR-0003)
- ADR-0012 (`agent-memory-orchestrator-mediated`) — the mediated-memory model that makes `memory:
  project` (shown in blueprint sec. 3.1's historical code block) correctly absent from the deployed
  file today; not reintroduced by this ADR
- ADR-0013 (`native-subagent-memory-supersede-mediated`) — the 2026-05-25 pilot this ADR's Alternatives
  §3.3 cites directly: an architect dispatch with a broad, unscoped `Write` grant (`memory: local`)
  autonomously edited a file **outside its declared write scope**. The same class of risk (unscoped
  `Write`) is present in today's `architect.md` for a different reason (the field was simply never
  scoped), and this ADR's investigation into whether it is fixable at the frontmatter layer, and why
  it is not, is a direct continuation of that pilot's finding
- ADR-0016 (`dynamic-workflows-step5`) — the `hook_verified` smoke-test-before-deploy gate this ADR's
  §3.6 (researcher `mcpServers`) cites as precedent for deferring an unverified platform-behavior
  change rather than deploying it unattended
- ADR-0020 (`autopilot-build-skill`), ADR-0022 (`nightly-autopilot-goal`), ADR-0023
  (`nightly-auto-design`) — the unattended chains whose architect dispatches this ADR's §3.2
  (`permissionMode: plan`) decision protects; all three depend on architect completing its Write
  deliverable with no human present to clear an approval prompt
- ADR-0024 (`vendor-deployed-only-skills-and-hooks`), ADR-0025 (`refresh-stale-staging-copies`) —
  established `staging/` as this roadmap's working source of truth, confirmed the three agent files
  this ADR edits carry **no** `sync-to-claude.sh` `PAIRS` entry (grepped before writing this ADR — zero
  hits for `agents/architect`, `agents/reviewer`, `agents/researcher`), so agent files reach `~/.claude`
  by a path outside the incremental `PAIRS` sync this ADR does not need to touch
- ADR-0029 (`hook-verify-session-filter`) — second precedent for the same
  verify-before-trust posture applied in §3.6
- ADR-0027 (`c2c-bsd-slug-autopilot-gates`), ADR-0028 (`manifest-helpers-guards`), ADR-0030
  (`scope-guards`), ADR-0035 (`skill-text-corrections`) — structural and test-harness precedent this
  ADR reuses directly (multi-finding issue, one shared hermetic test file, lettered sections,
  `ok`/`bad`/`PASS`/`FAIL` idiom, plus ADR-0035's exact "one RED task, N GREEN tasks, one wiring task"
  sequencing for a static-content-only fix)
- `docs/vibe-coding-system.md` sec. 3.1 (architect), 3.3 (reviewer), 3.8 (researcher), 3.9 (agent
  frontmatter field reference), 3.10 (cost model), and the "Changes from previous versions" changelog
  block (~line 423-462) whose dated-correction convention this ADR follows; sec. 7.4/7.5's
  "CORRECTION — this example is WRONG" admonition (~line 1383) is the direct style precedent for §2.4's
  blueprint edit
- `staging/plugin/agents/architect.md`, `staging/plugin/agents/reviewer.md`,
  `staging/plugin/agents/researcher.md` — the three files this ADR patches, confirmed byte-identical to
  the deployed `~/.claude/agents/` copies by diff before writing this ADR (read-only comparison; no
  file under `~/.claude` is modified by this ADR or its plan)
- `staging/plugin/scripts/protect-files.sh`, `staging/plugin/scripts/pre-flight-pattern-enforce.sh` —
  read during investigation; confirmed neither hook enforces a per-agent write-path allowlist for
  `architect` (`protect-files.sh` is a global denylist covering `.env`/secrets/`.git`/etc. for every
  agent; `pre-flight-pattern-enforce.sh` bails unless `agent_type == "coder"`, confirmed by its own
  header comment and `hook-probe-verify.sh`'s documented findings) — the residual gap §3.3 discusses
- External verification, via the `context7` MCP, of `code.claude.com/docs`: `/en/sub-agents`,
  `/en/agent-sdk/permissions`, `/en/agent-sdk/agent-loop`, `/en/model-config`, `/en/tools-reference`,
  `/en/permissions`, `/en/cli-reference`, `/en/plugins-reference`, `/en/agent-sdk/typescript` — all
  fetched 2026-07-11, cited by section below
- Implementation plan: `docs/superpowers/plans/2026-07-11-40-agent-tool-scoping.md`

---

## 1. Context

Issue #40 names four places where `staging/plugin/agents/{architect,reviewer,researcher}.md` (refreshed
from the deployed `~/.claude/agents/` tree by issue #29 — confirmed still byte-identical to the deployed
copies by diff before this ADR was written, so every finding below is live in production, not just in
`staging/`) disagree with blueprint sec. 3, with no note recording why. SPEC.md's own instruction: "the
ADR produced by this feature's chain decides which side wins and records why." Each finding was
re-verified against the current file state before this ADR was written, and — because the question is
literally "does blueprint's documented Claude Code behavior still hold" — each was additionally checked
against current `code.claude.com/docs` via the `context7` MCP rather than taken on the blueprint's own
word, per this agent's own Process step 2 (external dependency verification) and this document's
established "verified vs assumed" discipline.

### Finding 1 — `architect.md` (P2): unrestricted `Bash`, unscoped `Write`, `permissionMode: plan` absent

Deployed `tools:` reads `Read, Grep, Glob, Bash, WebSearch, WebFetch, Write, mcp__plugin_context7_context7__resolve-library-id, mcp__plugin_context7_context7__query-docs`
— bare `Bash` (no command-pattern restriction at all) and bare `Write` (no path restriction). Blueprint
sec. 3.1 specifies `Bash(git *), Bash(rg *)` and a top-level `permissionMode: plan`, neither present
today. ADR-0013 §Rejected-after-pilot already recorded a concrete incident of the same risk class: an
architect dispatch with a broad `Write` grant (there, via `memory: local`) "autonomously edited the
curated auto-memory... OUTSIDE its write-scope." Today's unscoped `Write` is structurally the same
exposure for a different reason — the field was simply never scoped in the first place.

### Finding 2 — `reviewer.md` (P2): unrestricted `Bash`

Deployed `tools:` reads `Read, Grep, Glob, Bash, LSP` — bare `Bash`. Blueprint sec. 3.3 specifies
`Bash(git diff*), Bash(git log*)` (read-only git inspection only — no `git add`/`git commit`). The
reviewer's own prompt body already states an invariant the frontmatter does nothing to enforce: "Use
Bash only for read-only inspection... Never run mutating git or shell commands." Reviewer processes
untrusted diff content (Core Responsibilities item 1: "Identify the recent changes"), so an unscoped
`Bash` grant is a real injection surface, not a theoretical one — and the live allow list this project
already ships (`staging/user/settings.json`) pre-approves `git add*`/`git commit*` at the session level,
so an injected mutating command routed through reviewer's unscoped `Bash` would not even prompt.

### Finding 3 — `architect.md` effort pin (P3): `max` vs blueprint's `xhigh`

Deployed frontmatter reads `effort: max`. Blueprint sec. 3.10's cost-model table pins `xhigh` for
architect with an explicit rationale ("Native default for Opus... Automatic fallback to `high` if
dispatched with `model: sonnet` override"). No note anywhere records why the deployed file diverged.

### Finding 4 — `researcher.md` (P3): no inline `mcpServers`, relies on the global plugin

Deployed frontmatter carries `tools: Read, Grep, Glob, WebSearch, WebFetch,
mcp__plugin_context7_context7__resolve-library-id, mcp__plugin_context7_context7__query-docs` and no
`mcpServers:` block. Blueprint sec. 3.8 shows an inline `mcpServers: context7: {command: npx, args:
[...]}` block plus a 2026-05-29 deployment note claiming "`mcpServers: context7` added inline. This
makes researcher self-contained." That claim does not match deployed or staging reality — confirmed no
inline block exists in either copy.

### Cross-check — what else was searched and confirmed compatible or out of scope

- `staging/sync-to-claude.sh`'s `PAIRS` block: grepped for `agents/architect`, `agents/reviewer`,
  `agents/researcher` — zero hits, for any of the eight agent files, not just these three. Agent files
  reach `~/.claude` by a path this ADR's plan does not need to add a `PAIRS` entry for (unlike ADR-0035
  Finding A, which closed exactly this kind of gap for a *skill* file).
- `staging/plugin/scripts/protect-files.sh` (the only hook wired to `PreToolUse` on `Edit|Write` for
  every agent, per `staging/plugin/hooks/hooks.json`): a global denylist (`.env`, secrets, `.pem`,
  `.key`, credentials, `/.git/`, `package-lock.json`). It does not scope `architect` to
  `docs/architecture/**`; it never did. This is the compensating control §2.1/§3.3 discuss the limits
  of, not a new one this ADR introduces.
- `staging/plugin/scripts/pre-flight-pattern-enforce.sh`: gates `coder` only (its own header: "gate for
  coder agent"; confirmed by `hook-probe-verify.sh`'s own documented finding, "bails at its agent_type
  check and enforces nothing" for any agent that is not `coder`). Not a control on `architect` or
  `reviewer` today, and this ADR does not extend it to them (see §3.3).
- `staging/plugin/agents/{coder,tester,debugger,doc-writer,refactorer}.md`: not named by SPEC's scope;
  spot-read for incidental consistency only, no divergence of this ADR's kind found, not edited.
- `.markdownlint-cli2.jsonc`: `staging/plugin/agents` is in the `ignores` glob list ("content fidelity
  to the deployed copy takes precedence over lint compliance for these subtrees") — the three edited
  agent files are exempt from the lint gate; this ADR file itself, under `docs/architecture/`, is not
  exempt and was run through `npx markdownlint-cli2` before being considered final (§6 references the
  result).

---

## 2. Decision

Reconcile each finding independently — none of the four shares a single resolution shape. Two
(architect Bash, reviewer Bash) restore blueprint's literal scope and add a narrow, evidenced widening
recorded as a deliberate divergence. One (architect `permissionMode`) is decided **against** restoring
blueprint, for a verified, structural reason. One (architect effort) is a straightforward correction
back to blueprint. One (researcher `mcpServers`) corrects a syntax error discovered *in* the blueprint
itself and defers deployment pending a smoke test neither this agent nor this pass can perform.

### 2.1 Finding 1a — architect `Bash`: restore blueprint's two entries, add four verification entries

New `tools:` line for `staging/plugin/agents/architect.md`:

```
tools: Read, Grep, Glob, Bash(git *), Bash(rg *), Bash(bash *), Bash(npx *), Bash(python3 *), Bash(shasum *), WebSearch, WebFetch, Write, mcp__plugin_context7_context7__resolve-library-id, mcp__plugin_context7_context7__query-docs
```

`Bash(git *)` and `Bash(rg *)` are blueprint's own text, byte-for-byte, including the space before `*`
— verified via `code.claude.com/docs/en/permissions` (fetched 2026-07-11): "Using a space before a
wildcard... enforces a word boundary," so `Bash(git *)` matches `git log`, `git diff`, `git show`, etc.
but not an unrelated command that merely starts with the letters "git". The four additions
(`Bash(bash *)`, `Bash(npx *)`, `Bash(python3 *)`, `Bash(shasum *)`) are not in blueprint's text; each is
independently evidenced by this roadmap's own live usage across the twelve architect dispatches that
produced ADR-0026 through ADR-0035: running the local hermetic test harness to verify a baseline before
proposing a fix, `npx markdownlint-cli2` as a self-check (this ADR's own §6 test-cmd relies on it —
required by this feature's own constraints), `python3` one-liners to sanity-check YAML/frontmatter
shape, and `shasum` for content-identity checks (e.g. confirming staging/deployed byte-identity, as done
in §1 above). None of `rm`, `mv`, `chmod`, `curl`/`wget`, `sed -i`, `dd`, `git commit`/`git push`, or any
package-install command (`pip install`, `npm install`) is in the allowlist — the six entries together
are still a **materially narrower** grant than today's bare `Bash`, not a relabeling of it.

### 2.2 Finding 1b — architect `permissionMode: plan`: do not restore

`permissionMode: plan` is **not** added to `architect.md`. Verified via
`code.claude.com/docs/en/agent-sdk/permissions` (fetched 2026-07-11): "Plan mode allows Claude to
explore the codebase and propose changes without executing file edits. Read-only tools function
normally, but any file modifications will prompt for approval through the `canUseTool` callback,
**regardless of existing allow rules**." And `code.claude.com/docs/en/agent-sdk/agent-loop`: "'plan'
prevents source file edits during exploration." This is an unconditional block on writes pending manual
approval — not a narrower permission grant that an allow-listed `Write` could route around. Architect's
entire deliverable, every single dispatch, is `Write`-ing exactly two files (the ADR and the plan) — see
Core Responsibilities items 3 and this document's own Output Format. Under `permissionMode: plan`, both
writes would need a `canUseTool` approval with no human present in the three chains that dispatch
architect unattended today: `autopilot-build` (ADR-0020), `nightly-autopilot` (ADR-0022), and
`nightly-autopilot`'s Phase P design generation (ADR-0023) — including the run producing this very ADR
(manifest `autopilot: true`, "Auto mode active, no intermediate HITL"). Restoring the field would not
harden architect; it would silently prevent it from ever completing its job unattended, with no error
surfaced beyond a stalled or denied tool call. This is a deliberate, ADR-recorded divergence, not an
oversight to fix — see §3.2 for the alternatives considered and why each was rejected.

### 2.3 Finding 1c — architect `Write` path scoping: no frontmatter-level fix exists; disclosed as a residual gap

Investigated whether Claude Code supports a path-scoped `Write` permission rule analogous to `Edit`'s
documented path-pattern matching (which would let `tools:` read `Write(docs/architecture/**)` the same
way `Bash(git *)` scopes `Bash`). Verified via `code.claude.com/docs/en/tools-reference` (fetched
2026-07-11), stated twice across two independent doc fetches: "Bash and Monitor use command pattern
matching, while Read, Grep, and Edit use path pattern matching." `Write` is not in that list, in either
fetch. No documented syntax exists to scope `Write` to a path glob. `architect.md`'s own body already
carries a prompt-level instruction ("Write scope: you may only write under `docs/architecture/**`.
Never edit source, config, or tests" — Edge Cases, unedited by this ADR), and the global
`protect-files.sh` hook (§1 Cross-check) blocks a fixed denylist for every agent regardless of identity.
Neither is a structural, per-agent write-path allowlist; ADR-0013's pilot already demonstrated that a
prompt-level instruction alone does not reliably hold when the tool grant itself does not enforce it.
This ADR does not close that gap — doing so would mean designing and testing a new, `architect`-scoped
`PreToolUse` hook (the same shape as `pre-flight-pattern-enforce.sh`, but keyed on `agent_type ==
"architect"` and a path allowlist instead of a `PATTERN:` header), which is new hook development outside
SPEC's four named findings and this issue's `In:` scope (`staging/plugin/agents/` only). Disclosed here,
and in Consequences/Negative, as a known, unchanged residual risk — not a silent omission.

### 2.4 Finding 3 — architect `effort`: `max` → `xhigh`

`effort: xhigh` replaces `effort: max`. Verified via `code.claude.com/docs/en/model-config` (fetched
2026-07-11): "Persistent settings can be defined in a configuration file, though 'max' and 'ultracode'
levels are restricted to session-only use." An agent's own `.md` frontmatter is read fresh from disk on
every dispatch — it is file-based, persistent configuration, not a live interactive session — so
`effort: max` sitting in `architect.md` is very likely inert (either rejected at load or silently
resolved to some other tier), while simultaneously misleading anyone reading the file into believing
`max` is actually enforced. Blueprint sec. 3.10 already gives the correct, working alternative with its
own rationale ("Native default for Opus... Automatic fallback to `high` if dispatched with `model:
sonnet` override"). This is a plain correction back to a working, documented value, not a divergence
needing a compensating control.

### 2.5 Finding 2 — reviewer `Bash`: restore blueprint's two entries verbatim, add three verification entries

New `tools:` line for `staging/plugin/agents/reviewer.md`:

```
tools: Read, Grep, Glob, Bash(git diff*), Bash(git log*), Bash(bash *), Bash(awk *), Bash(python3 *), LSP
```

`Bash(git diff*)` and `Bash(git log*)` are blueprint's own text, byte-for-byte, including the *absence*
of a space before `*` (verified: this still restricts to commands literally beginning `git diff`/`git
log`, and additionally reaches git's own plumbing variants like `git diff-index`/`git diff-tree`, which
is consistent with reviewer's read-only-inspection purpose — not loosened by this ADR). Critically,
`git add*`/`git commit*`/`git push*` are **not** added — reviewer's own prompt-body invariant ("Never
run mutating git or shell commands") stays true at the tool-permission layer as well as the prompt
layer, which it is not today. The three additions (`Bash(bash *)`, `Bash(awk *)`, `Bash(python3 *)`)
mirror the evidenced need from this roadmap's own reviewer dispatches (running the project's test
harness, `awk`-based trace inspection, YAML/JSON parsing via `python3`) and the `review-triage-fix`
skill's design assumption of verification by direct execution, not just reading. This set is
deliberately **narrower** than architect's (§2.1): no `npx`, no `shasum`, no bare `git *` — reviewer's
threat model (processing untrusted diff content, per Finding 2) warrants the tighter set. `LSP` is
unchanged, not part of SPEC's named findings.

### 2.6 Finding 4 — researcher `mcpServers`: correct the blueprint's stale syntax, defer deployment

`staging/plugin/agents/researcher.md` is **not edited** by this ADR. Blueprint sec. 3.8 and its
duplicate example in sec. 3.9 are corrected in place: the map-keyed form (`mcpServers: context7:
{command: npx, args: [...]}`) does not match the syntax documented at
`code.claude.com/docs/en/sub-agents` (fetched 2026-07-11), which shows `mcpServers` as a YAML **list**,
each inline entry keyed by server name with an explicit `type: stdio` field:

```yaml
mcpServers:
  - context7:
      type: stdio
      command: npx
      args:
        - -y
        - "@upstash/context7-mcp"
```

This corrects a real defect in the blueprint (a template meant to be copy-pasted, per this repository's
own `CLAUDE.md`: "checklists... and templates... are intended to be copied into other repos: keep them
self-consistent and valid as standalone documents") independent of what researcher.md itself does. The
existing 2026-05-29 deployment note at sec. 3.8 ("This makes researcher self-contained") is left in
place as the historical record of the original intent (mirrors this document's own established
convention — sec. 8.3's design catalog is "historically accurate, not a live-status claim") and a new,
dated note is appended directly beneath it correcting the live-status claim and explaining the deferral.
See §3.6 for why deployment is deferred rather than applied with the corrected syntax.

### 2.7 Blueprint edit mechanism

Mirrors this document's own established convention exactly (sec. 7.4/7.5's "CORRECTION — this example
is WRONG" admonition; coder's stacked two-paragraph deployment notes at ~line 703-704; the two existing
`### Correction 2026-07-11 (...)` changelog entries at ~line 423 and ~line 441): a new, third
`### Correction 2026-07-11 (issue #40, agent tool scoping reconciliation)` changelog entry is appended
after the existing two same-day corrections (before `### Update 2026-06-23`), and short deployment-note
blockquotes are added directly under sec. 3.1 and sec. 3.3 (new) and appended to sec. 3.8's existing
note (stacked, not replacing). No historical code block is rewritten in place except the `mcpServers`
YAML itself (§2.6) and its sec. 3.9 duplicate, and the sec. 3.9 field-reference table cell describing
`mcpServers`'s value shape (`YAML map` → `YAML list`, matching the corrected example beneath it) —
justified in §3.6 as a syntax-correctness fix, not a design-history rewrite, and thus not subject to the
"historical record" carve-out sec. 8.3 established for design decisions. Section numbering (3.1 through
3.10) is unchanged; every heading is confirmed present, in order, before and after.

### 2.8 Test strategy

One new hermetic file, `staging/plugin/scripts/tests/agent-tool-scoping.test.sh`, five lettered sections
(A-E: architect frontmatter, reviewer frontmatter, researcher frontmatter non-regression, blueprint
changelog + sec. 3.1/3.3 notes, blueprint sec. 3.8/3.9 syntax correction), reusing the exact
`ok()`/`bad()`/`PASS`/`FAIL` idiom and `frontmatter_ok` structural-parse helper established by
ADR-0027/0028/0030/0035, plus two positional checks (deployment notes land under the correct
subsection, not merely somewhere in the document) following ADR-0035 §2.6's precedent for the same
category of structural requirement. Every assertion is a static grep/positional check against real file
content on disk — no dynamic fixtures, matching ADR-0035 §3.8's reasoning for this class of change
(prose/frontmatter edits with no runtime behavior to extract and execute). Wired into
`.github/workflows/docs-ci.yml`'s explicit `shell-tests` list (fourteenth entry) and picked up
automatically by `.claude/test-cmd`'s existing wildcard glob.

---

## 3. Alternatives considered

### 3.1 Architect `Bash` — how wide to scope beyond blueprint's literal text

- **Alt A1 — restore blueprint's exact `Bash(git *), Bash(rg *)`, nothing more.** **Rejected:** this
  roadmap's own architect dispatches (the twelve that produced ADR-0026 through ADR-0035, including this
  one) routinely and demonstrably use `bash` to run the local test harness, `npx markdownlint-cli2` for
  the self-lint this feature's own constraints require, `python3` for structural sanity checks, and
  `shasum`/plain read utilities for verification. A literal restore would silently remove a working,
  valuable verification discipline this project has relied on across the entire roadmap, trading one
  under-scoped risk for a different regression (an architect that can no longer verify its own claims —
  directly contradicting this agent's own Quality Standards and the global `CLAUDE.md` instruction "If
  you cannot verify a result, say so — do not assume it works").
- **Alt A2 — leave `Bash` fully unrestricted, record the widening as a deliberate divergence with no
  narrowing at all.** **Rejected:** this is the status quo, and the status quo is the reported defect.
  An unrestricted grant admits `rm -rf`, `git push --force`, `curl | sh`, and every other destructive or
  exfiltration-capable command with zero structural gate — "deliberate" does not make an unbounded grant
  a compensating control; it is simply not one. SPEC's own edge case requires a compensating control for
  any kept divergence, not just a recorded one.
- **Chosen: Alt A3 — restore blueprint's two entries verbatim, add four independently-evidenced,
  narrowly-scoped verification-tool entries (§2.1).** Preserves the safety property blueprint's own
  scoping was designed to provide (no arbitrary shell access) while preserving the verification
  capability this project's own operating history shows architect actually needs. Each addition is
  independently justified, not a blanket re-opening.

### 3.2 Architect `permissionMode: plan` — restore, compensate, or drop

- **Alt B1 — restore `permissionMode: plan` as blueprint specifies.** **Rejected:** verified (§2.2) to
  block every file write pending manual approval "regardless of existing allow rules." Architect's sole
  deliverable is two file writes per dispatch. This would not hazard-reduce architect; it would break
  its ability to complete a dispatch unattended, in every chain this project has built specifically to
  run architect without a human present (ADR-0020, ADR-0022, ADR-0023) — including this dispatch itself.
- **Alt B2 — restore `permissionMode: plan`, and build a compensating auto-approval mechanism (e.g. a
  `PreToolUse` hook or a custom `canUseTool` callback that auto-approves `Write` calls scoped to
  `docs/architecture/**`).** **Rejected for this ADR:** this is not a frontmatter change — it is new
  infrastructure (a hook or an Agent-SDK-level `canUseTool` integration) outside SPEC's `In:` scope
  (`staging/plugin/agents/` only) and outside what a documentation-only repository with no application
  code can build and test in this pass. It would also need its own smoke test before being trusted
  unattended, the same posture §3.6 applies to the researcher `mcpServers` question — compounding two
  unverified changes in one ADR is worse practice than resolving them independently. If the residual
  `Write`-scope gap (§2.3) is ever judged to need closing, this is the mechanism a future, dedicated
  issue should build and verify — not a byproduct of this one.
- **Chosen: Alt B3 — do not restore `permissionMode: plan`; record the decision and its verified
  reasoning (§2.2).** The only alternative that does not either break unattended operation (B1) or
  require unbuilt, untested infrastructure in the same pass (B2). Matches SPEC's own edge case exactly:
  "A divergence judged deliberate: ADR records it with a compensating control" — here the compensating
  control is the Bash-scope narrowing (§2.1) plus the disclosed, unchanged `Write`-scope gap (§2.3),
  not a new mechanism this ADR invents to paper over an unverified restoration.

### 3.3 Architect `Write` path scoping — attempt a frontmatter fix, or disclose the gap

- **Alt C1 — invent a plausible path-scoped syntax (e.g. `Write(docs/architecture/**)`) and add it
  anyway, on the theory that an unrecognized rule fails safe (ignored) rather than fails open (granted
  broader than intended).** **Rejected:** "fails safe" is an assumption this ADR has no verification for
  either way — `code.claude.com/docs/en/tools-reference` names `Write` as one of the tools that support
  parenthesized specifiers at all only implicitly (by omission from the "Read, Grep, and Edit use path
  pattern matching" list, checked twice, identically, across independent fetches); an unrecognized or
  malformed specifier could just as plausibly cause a parse failure for the whole `tools:` line, silently
  falling back to full inheritance — the opposite of the intended effect, and worse than today's
  explicit, at-least-visible bare `Write`. Shipping unverified, guessed syntax into a production agent
  file, unattended, fails this document's own "never promote an assumption to a fact without
  verification and a citation" discipline.
- **Alt C2 — build a new `architect`-scoped `PreToolUse` hook enforcing the path allowlist
  structurally, the same shape as `pre-flight-pattern-enforce.sh` but keyed on `agent_type ==
  "architect"`.** **Rejected for this ADR, not permanently:** real hook development, its own test
  harness, and its own smoke test (mirroring ADR-0016's `hook_verified` gate) — a materially larger unit
  of work than SPEC's four named, frontmatter-only findings, and outside this issue's `In:` scope
  (`staging/plugin/agents/`). ADR-0013's pilot already showed this exact risk manifesting once; a
  dedicated follow-up issue is the right unit of work to close it properly, not a rider on this one.
- **Chosen: Alt C3 — verify no frontmatter-level fix exists, leave `Write` as today (unscoped), disclose
  the gap explicitly in this ADR's Decision and Consequences/Negative (§2.3).** The only option that
  neither ships unverified syntax (C1) nor scope-creeps a new hook into a frontmatter-reconciliation
  issue (C2), while still being honest that the risk ADR-0013's pilot already surfaced once remains
  open.

### 3.4 Architect `effort` — `max`, `xhigh`, or `high`

- **Alt D1 — keep `effort: max`.** **Rejected:** verified (§2.4) that `max` does not persist in
  file-based configuration, making the pinned value very likely inert on every dispatch — keeping it
  preserves a misleading, probably-non-functional setting with no offsetting benefit.
- **Alt D2 — set `effort: high` (the fallback blueprint sec. 3.10 itself documents for `xhigh` on models
  that do not support it).** **Rejected:** unnecessary — sec. 3.10 and sec. 3.9's "Available effort
  levels by model" table both confirm Opus 4.8 supports `xhigh` natively; falling back to `high`
  pre-emptively would under-use a capability the target model actually has, for no reason tied to this
  finding.
- **Chosen: Alt D3 — set `effort: xhigh`, matching blueprint sec. 3.10 exactly (§2.4).** The value
  blueprint's own cost-model rationale already argues for, and the one Opus 4.8 actually supports.

### 3.5 Reviewer `Bash` — mirror architect's full addition set, or scope narrower

- **Alt E1 — give reviewer the identical six-entry set architect gets (§2.1), for consistency between
  the two agents.** **Rejected:** reviewer's own threat model is materially different from architect's —
  Finding 2 names it directly: reviewer processes untrusted diff content, is the pre-commit gate, and
  its own prompt body already states "Never run mutating git or shell commands" as a hard invariant.
  `Bash(npx *)` and `Bash(shasum *)` have no evidenced reviewer use case (unlike architect's, where
  `npx markdownlint-cli2` and content-hash verification are both directly used), and granting them
  anyway "for consistency" would widen reviewer's surface with no offsetting justification — the
  opposite of the least-privilege reasoning this whole ADR is built on.
- **Alt E2 — restore only blueprint's exact `Bash(git diff*), Bash(git log*)`, no additions at all,
  matching Finding 1's Alt A1 symmetry.** **Rejected for the same reason Alt A1 was rejected for
  architect:** this roadmap's reviewer dispatches demonstrably run test suites, `awk` traces, and YAML
  parses as part of the verification-by-execution the `review-triage-fix` skill's design assumes.
  Restoring only the two git patterns would silently remove that capability.
- **Chosen: Alt E3 — restore blueprint's two git entries verbatim, add exactly the three
  evidenced-necessary, execution-only entries (`bash`, `awk`, `python3`) — narrower than architect's set
  (§2.5).** Matches reviewer's own stricter, already-declared non-mutating identity while preserving its
  evidenced verification need.

### 3.6 Researcher `mcpServers` — deploy the corrected block, fix the doc only, or leave both as-is

- **Alt F1 — leave blueprint sec. 3.8/3.9 exactly as written (map-keyed, no `type: stdio`), and add that
  same, now-confirmed-stale, syntax to `researcher.md`'s live frontmatter, matching SPEC's stated default
  expectation literally.** **Rejected:** would ship syntax this ADR has independently verified does not
  match `code.claude.com/docs/en/sub-agents`'s current documented form into a production agent file,
  unattended, with no way to confirm it actually connects or that its tools become reachable — the same
  "unverified assumption shipped unattended" problem Alt C1 (§3.3) rejects for a different field.
- **Alt F2 — correct the blueprint's syntax (this ADR's own verified finding) *and* deploy the corrected
  block to `researcher.md`, on the reasoning that the corrected syntax is well-sourced (two independent,
  identical fetches from the canonical `code.claude.com/docs/en/sub-agents` page) and the worst case if
  some remaining assumption is still wrong is a redundant, unused server connection alongside the
  already-working global-plugin tools (which stay in `tools:` unchanged either way).** **Rejected, but
  closer:** the *syntax* is well-verified; what is not verified is whether an inline-scoped server named
  `context7` produces tool names reachable under the `tools:` entries already granted
  (`mcp__plugin_context7_context7__*`, sourced from the global plugin) or a different, unlisted prefix
  (`mcp__context7__*` or similar) that would need its own `tools:` entry to actually be usable —
  and this agent has no `Task`/`Agent` tool to dispatch a live researcher run and observe which is true
  before trusting the answer. This project's own precedent for exactly this situation (ADR-0016's
  `hook_verified` gate, ADR-0029's session-filter verification) is: block deployment of a
  platform-behavior-dependent change until a live smoke test confirms it, not deploy on a well-sourced
  but unconfirmed inference.
- **Chosen: Alt F3 — correct the blueprint's syntax in place (sec. 3.8 and its sec. 3.9 duplicate), leave
  `researcher.md` unedited, and record the deferral with its exact unblocking condition (§2.6).** Matches
  SPEC's own explicitly sanctioned success criterion ("researcher matches blueprint 3.8, **or** the 3.8
  deployment note is corrected to describe plugin-tool reliance") without gambling an unverified change
  on a currently-working, actively-relied-upon research capability for a P3-priority item.

### 3.7 Blueprint edit mechanism — in-place rewrite, changelog-only, or stacked deployment notes

- **Alt G1 — rewrite sec. 3.1/3.3/3.8's example code blocks in place to show the new, corrected/widened
  frontmatter directly, no separate note.** **Rejected:** breaks this document's own established
  convention, applied consistently from the very first "Correction 2026-05-19" entry onward, of never
  silently rewriting a historical example — sec. 7.4/7.5 kept the wrong JSON example and added a
  dated admonition instead of deleting it ("The JSON example below is kept for historical reference
  only"); sec. 8.3's design catalog was explicitly left untouched because it is "historically accurate,
  not a live-status claim." Rewriting the sec. 3.1/3.3/3.8 code blocks in place would erase the record of
  what blueprint originally specified, which is exactly the information this ADR needs readers to be
  able to compare against.
- **Alt G2 — record the reconciliation only in the top-of-document changelog, add no note at the
  specific sections.** **Rejected:** a reader landing directly on sec. 3.1 (the far more likely entry
  point when re-checking one agent's configuration than the ~2500-line changelog block) would see
  blueprint's original, now-superseded-in-part text with no indication anything changed — exactly the
  silent-drift failure mode this whole ADR exists to close.
- **Chosen: Alt G3 — both: one comprehensive changelog entry (the primary record, §2.7) plus short,
  pointer-style deployment-note blockquotes at sec. 3.1, 3.3, and appended to sec. 3.8's existing note
  (§2.1-§2.6), mirroring the exact two-tier structure this document already uses for the coder
  `isolation`/`memory` changes (~line 703-704) and the researcher `mcpServers` note (~line 899) it is
  extending.** Consistent with precedent, and gives both a reader entering from the changelog and one
  entering from section 3 directly the correction without re-litigating it in four separate, fully
  independent essays. The one exception (§2.7): the `mcpServers` YAML itself and the sec. 3.9 table cell
  describing its shape are corrected in place, not just annotated, because a syntax error in a
  copy-paste template is a factual defect, not a superseded design decision — the same category
  sec. 7.4/7.5's admonition itself belongs to (a wrong technical claim, corrected with a dated marker,
  not silently repaired).

### 3.8 Test harness task granularity

- **Alt H1 — interleave RED and GREEN tasks per section (ten tasks for five sections), matching
  ADR-0027/0028/0030's structure.** **Rejected for this issue specifically, for the identical reason
  ADR-0035 §3.8 gives:** every assertion in this ADR's test file is a static grep/positional check
  against frontmatter or blueprint prose already on disk — no dynamic fixture, no extract-and-execute
  helper, no exit-code edge case to pin down section-by-section. Interleaving would add task-count
  overhead with no added safety.
- **Chosen: Alt H2 — one RED task (full five-section file, confirmed genuinely failing where expected),
  four GREEN tasks (one per edited unit: architect, reviewer, blueprint changelog+notes, blueprint
  mcpServers syntax), one wiring/regression task — six tasks total (§2.8).** Preserves genuine TDD
  without paying for interleaving structure this issue's static-only assertions do not need; matches
  ADR-0035's precedent file-format conventions exactly while adapting task count to one fewer edited
  unit (three agent files collapse to two edited + one non-regression, versus ADR-0035's five edited
  files).

---

## 4. Consequences

### Positive

- Architect and reviewer both go from **fully unrestricted `Bash`** (any command, no gate at the
  frontmatter layer at all) to a small, named, independently-justified allowlist — a structural
  narrowing verified against current `code.claude.com/docs` syntax, not a cosmetic relabeling. Neither
  agent can *directly* invoke `rm`, `mv`, `chmod`, fetch-and-pipe (`curl`/`wget`), `sed -i`, package
  installs, or push/force-push/commit (reviewer) after this ADR, where all of that was available,
  ungated, before it. **This direct-invocation claim is qualified, not absolute:** the interpreter-class
  grants (`bash`, `python3`, `awk` — see Consequences/Negative) can wrap any of those commands
  (`bash -c "git commit ..."`, `python3 -c "os.system(...)"`), so the exclusion is a guard against
  accidental/pattern-matched misuse and an audit-trail improvement, not a hard capability boundary.
  The hard boundary requires hook-level command inspection — the same follow-up unit of work as the
  `Write`-scope gap (§2.3).
- The `permissionMode: plan` question is resolved with an actual verified answer instead of staying an
  unexplained, silent drift: restoring it would have quietly broken every unattended architect dispatch
  in `autopilot-build`, `nightly-autopilot`, and `nightly-autopilot`'s Phase P — a regression that could
  have gone undetected for a long time, since a stalled or denied `Write` call inside an unattended chain
  fails in a way that is easy to misattribute to something else. This ADR closes that investigation
  permanently (until Claude Code's own documented plan-mode semantics change) rather than leaving it to
  be rediscovered by a future outage.
- The `effort: max` finding surfaces a broader, reusable fact for this project: `max`/`ultracode` effort
  levels do not persist in file-based configuration. Worth checking on any *other* agent file that might
  carry `effort: max` in the future, not just this one instance.
- A real syntax defect in blueprint's `mcpServers` template (present in two places, sec. 3.8 and 3.9) is
  found and corrected, independent of what happens to `researcher.md` itself — the next agent or project
  that copy-pastes this template gets working YAML instead of a stale, currently-unverifiable-to-parse
  form.
- The `Write`-path-scoping investigation (§2.3) converts a previously-implicit assumption ("architect's
  write scope is enforced, because the prompt says so") into an explicitly-disclosed, verified fact
  ("it is not enforced at the tool-permission layer, and current Claude Code syntax offers no way to do
  so for `Write`") — the same category of finding ADR-0013's pilot produced empirically, now confirmed
  by direct documentation research rather than by a second live incident.
- 6 architect assertions + 9 reviewer assertions + 3 researcher non-regression assertions + blueprint
  changelog/notes/syntax assertions extend `docs-ci.yml`'s `shell-tests` job from 13 to 14 entries,
  reusing the established `ok`/`bad`/`PASS`/`FAIL` idiom, `frontmatter_ok` helper, and lettered-section
  convention — zero ramp-up for a reviewer already familiar with this suite.
- Zero files under `~/.claude` touched; zero new hook, zero new skill, zero manifest schema change, zero
  `PAIRS` entry needed (none of the three agent files carries one today, for any agent, confirmed by
  grep before this ADR was written).

### Negative

- The `Write`-path-scoping gap (§2.3) is disclosed, not closed. Architect can still, at the tool-
  permission layer, write anywhere `protect-files.sh`'s denylist does not block — which is most of the
  filesystem. The compensating controls (prompt-level instruction, global denylist) are exactly what was
  in place before this ADR; nothing here reduces that specific exposure. ADR-0013's pilot already showed
  this class of control failing once under a different triggering field (`memory: local`); the same
  residual risk remains open under `Write` today. A dedicated follow-up issue (§3.3 Alt C2) is the
  correct unit of work to close it, not this one.
- Architect's Bash allowlist (`git`, `rg`, `bash`, `npx`, `python3`, `shasum`) is wider than blueprint's
  literal two-entry text, and reviewer's (`git diff`/`git log`, `bash`, `awk`, `python3`) is wider than
  its literal two-entry text. Both are deliberate, evidenced, and narrower than today's unrestricted
  grant, but a future reader comparing `staging/plugin/agents/` against blueprint sec. 3 line-by-line
  will still see a difference and needs to consult this ADR (linked from the deployment notes) to
  understand why it is intentional rather than a fresh, unrecorded drift of the same kind this ADR was
  written to close. The deployment notes and changelog entry are the mitigation, not a guarantee every
  future reader checks them.
- `researcher.md` keeps relying on the global `context7` plugin rather than becoming genuinely
  self-contained. If that plugin is ever absent from an environment this agent file is copied into (a
  scenario blueprint sec. 3.9's own scoping rule anticipates — "makes the agent self-contained when
  shared across repos"), researcher's context7 tools would not resolve, and this ADR does not fix that;
  it only stops the blueprint from claiming, incorrectly, that the problem is already solved.
- **Every interpreter-class grant — `Bash(bash *)` on both agents, `Bash(python3 *)` on both,
  `Bash(awk *)` on reviewer — is functionally a full-Bash bypass within its prefix**, not merely
  "broad": `bash -c "<anything>"`, `python3 -c "import os; os.system('<anything>')"`, and
  `awk 'BEGIN{system("<anything>")}'` each reach arbitrary commands, including the mutating git
  operations the reviewer allowlist deliberately excludes. `npx` shares the class
  (`npx <malicious-package>`); its entry is therefore tightened to the two evidenced markdownlint
  invocations rather than `npx *`. This ADR **explicitly accepts** the remaining bash/python3/awk
  residual: (1) the alternative — fully unrestricted `Bash` — is what exists today and is strictly
  worse (any command matched with zero audit trail); (2) the evidenced need is real — this roadmap's
  own 12 architect/reviewer dispatches ran test harnesses at arbitrary fixture paths and python3 YAML
  checks, and that verification-by-execution discipline caught genuine defects (ADR-0031, ADR-0033,
  ADR-0036 review cycles); (3) this is a documentation/staging repo whose PRs pass a morning human
  review before merge, and deployment to `~/.claude` is a separate manual step. The exclusion of
  `git add/commit/push` from reviewer's list is accordingly an accidental-misuse guard, not an
  adversarial boundary (see the qualified claim under Positive). Closing the residual for real means
  a `PreToolUse` hook that inspects wrapped commands — named here as the follow-up unit of work,
  alongside the `Write`-scope hook (§2.3/§3.3 Alt C2).
- The deployed `~/.claude/agents/{architect,reviewer,researcher}.md` copies keep today's four defects
  until a human runs the next sync — the same disclosed, established "deployed stays defective until
  sync" convention as ADR-0024 through ADR-0035, repeated here since these three files have no
  `sync-to-claude.sh` `PAIRS` entry to run `--apply` against; the deployment path for agent files is
  outside that incremental mechanism (§1 Cross-check) and is not designed or changed by this ADR.
- Blueprint's sec. 3.1/3.3 deployment notes and the changelog entry add roughly 40 lines to an already
  2550-line document; §3.7's rejected Alt G2 (changelog-only) would have added fewer lines but at the
  cost of section-3 readers missing the correction entirely — judged the wrong trade here, but it is a
  real, non-zero documentation-maintenance cost this ADR incurs going forward (every future reconciler
  of sec. 3 now has one more stacked note per touched agent to read before editing).

### Neutral

- No manifest schema change, no new hook, no new skill, no `settings.json` change anywhere in this ADR.
- `docs/manifests/2026-07-11-40-agent-tool-scoping.manifest.yml` is read but not edited by this ADR —
  populating `artifacts.adr`/`artifacts.plan` and advancing `current_step` is the orchestrator's
  responsibility per the chain's own design (ADR-0003), reported back via this ADR's final report, not
  performed here.
- `docs/vibe-coding-system.md`'s section numbering (3.1 through 3.10) is unchanged; every subsection
  heading confirmed present, in the same order, before and after this ADR's edits.
- `coder`, `tester`, `debugger`, `doc-writer`, `refactorer` are unaffected — SPEC's `Out:` scope
  explicitly excludes them beyond incidental consistency, and none was found to share this ADR's four
  findings on inspection.
- This ADR neither opens nor forecloses §3.2's Alt B2 (a dedicated `canUseTool`/hook mechanism to make
  `permissionMode: plan` safe for unattended architect writes) or §3.3's Alt C2 (a per-agent write-path
  hook) — both are explicitly left for a future, dedicated issue to pick up if the residual gaps they
  would close are ever judged worth the infrastructure investment.
- §3.6's Alt F2 (deploy the corrected `mcpServers` block to `researcher.md`) is not foreclosed either —
  the exact unblocking condition is stated in §2.6 and the sec. 3.8 deployment note: a live smoke test,
  from a context that has a `Task`/`Agent` tool available, confirming the resulting tool-name prefix is
  reachable under `tools:`.

---

## 5. References

- `SPEC.md` (repo root) / `docs/specs/40-agent-tool-scoping-per-blueprint-section.spec.md` — this
  issue's spec (confirmed byte-identical)
- GitHub issue #40 — confirmed the four-finding, three-file scope matches SPEC.md exactly
- `docs/manifests/2026-07-11-40-agent-tool-scoping.manifest.yml` — read for context (`current_step`,
  `autopilot: true`), not edited
- `docs/architecture/ADR-0012-agent-memory-orchestrator-mediated.md`,
  `docs/architecture/ADR-0013-native-subagent-memory-supersede-mediated.md` — the mediated-memory
  decision that keeps `memory: project` absent from `architect.md` today, and the 2026-05-25 pilot
  incident (`architect` + broad `Write` grant editing outside declared scope) this ADR's §2.3/§3.3 treat
  as the closest real-world precedent for the unscoped-`Write` risk
- `docs/architecture/ADR-0016-dynamic-workflows-step5.md` — the `hook_verified` smoke-test-before-deploy
  gate cited in §2.6/§3.6
- `docs/architecture/ADR-0020-autopilot-build-skill.md`,
  `docs/architecture/ADR-0022-nightly-autopilot-goal.md`,
  `docs/architecture/ADR-0023-nightly-auto-design.md` — the three unattended chains §2.2/§3.2's
  `permissionMode: plan` decision protects
- `docs/architecture/ADR-0024-28-vendor-deployed-only-skills-and-hooks.md`,
  `docs/architecture/ADR-0025-29-refresh-stale-staging-copies.md` — `staging/` as source of truth;
  confirmed no `PAIRS` entry exists for any agent file
- `docs/architecture/ADR-0029-33-hook-verify-session-filter.md` — second smoke-test-before-trust
  precedent cited in §3.6
- `docs/architecture/ADR-0027-31-c2c-bsd-slug-autopilot-gates.md`,
  `docs/architecture/ADR-0028-32-manifest-helpers-guards.md`,
  `docs/architecture/ADR-0030-34-scope-guards.md`,
  `docs/architecture/ADR-0035-39-skill-text-corrections.md` — structural, test-harness, and
  task-sequencing precedent reused directly (§2.8/§3.8)
- `docs/vibe-coding-system.md` sec. 3.1, 3.3, 3.8, 3.9, 3.10, and the "Changes from previous versions"
  changelog block (~line 10-462) whose dated-correction convention this ADR follows; sec. 7.4/7.5
  (~line 1381-1444) is the direct style precedent for the `mcpServers` in-place syntax correction
- `staging/plugin/agents/architect.md`, `staging/plugin/agents/reviewer.md`,
  `staging/plugin/agents/researcher.md` — the three files this ADR patches (researcher unedited by
  content, confirmed unchanged by this ADR's own plan)
- `staging/plugin/scripts/protect-files.sh`, `staging/plugin/scripts/pre-flight-pattern-enforce.sh`,
  `staging/plugin/hooks/hooks.json` — read to confirm neither hook enforces a per-agent write-path
  allowlist for `architect` or `reviewer` today
- `staging/sync-to-claude.sh` — grepped for `agents/architect`, `agents/reviewer`, `agents/researcher`;
  zero `PAIRS` entries for any agent file, confirming no sync-mechanism change is needed
- `.markdownlint-cli2.jsonc` — confirms `staging/plugin/agents` is lint-exempt; `docs/architecture/` is
  not, and this ADR was checked with `npx markdownlint-cli2` before being finalized
- `code.claude.com/docs/en/sub-agents`, `/en/agent-sdk/permissions`, `/en/agent-sdk/agent-loop`,
  `/en/model-config`, `/en/tools-reference`, `/en/permissions`, `/en/cli-reference`,
  `/en/plugins-reference`, `/en/agent-sdk/typescript` — fetched via the `context7` MCP, 2026-07-11;
  primary source for every verified-behavior claim in §2 and §3
- `.github/workflows/docs-ci.yml`, `.claude/test-cmd` — CI wiring for the new test file; the latter
  needs no edit (existing wildcard glob already covers it)
- Implementation plan: `docs/superpowers/plans/2026-07-11-40-agent-tool-scoping.md`
