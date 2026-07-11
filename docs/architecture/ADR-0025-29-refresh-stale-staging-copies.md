# ADR-0025 — Refresh stale staging copies from the deployed tree

**Status:** Accepted
**Date:** 2026-07-11
**Author:** istefox
**Supersedes:** none
**Superseded by:** none
**Related:**
- SPEC: `docs/specs/29-refresh-stale-staging-copies-from-the-de.spec.md` (= `SPEC.md` at repo root, GitHub issue #29)
- ADR-0022 (`nightly-autopilot-goal`) — established `staging/` + `sync-to-claude.sh` + PAIRS as the incremental
  single-file deploy path, and the `RUNBOOK.md` step-by-step bulk deploy procedure this ADR distinguishes it from
- ADR-0024 (`vendor-deployed-only-skills-and-hooks`) — the immediately preceding issue (#28): vendored 90
  previously-untracked files, extended PAIRS from 15 to 105 entries, and explicitly reserved `staging/plugin/agents/`,
  `staging/user/`, and 9 named repo-native skills (`adr-writer`, `claude-md-generator`, `code-review-checklist`,
  `commit`, `fastapi-react-vibe`, `interview-driver`, `project-conductor`, `spec-from-issue`, `swift-vibe`, plus
  `goal-loop`/`research-prompt`) as this issue's territory
- ADR-0001 (`coder-preflight-pattern-classifier`), ADR-0004 (`pre-flight-pattern-enforce-hook`) — the `PATTERN:`
  classifier convention absent from the staged `coder.md` before this refresh
- ADR-0012 (`agent-memory-orchestrator-mediated`) — retired the `docs/agent-notes/<agent>.md` file-based memory
  convention still present in four staged agent files before this refresh
- ADR-0014 (`architect-proposes-test-cmd`) — the `TEST-CMD CANDIDATE` / `DURABLE NOTES` architect output-block
  convention absent from the staged `architect.md` before this refresh
- ADR-0015 (`humanize-en-chain-integration`) — the English-prose humanization convention referenced by the staged
  vs. deployed skill-text drift this issue closes
- `docs/specs/38-hook-hardening-enum-value-lock-ownership.spec.md`, `docs/specs/39-skill-text-corrections-across-five-stand.spec.md`,
  `docs/specs/40-agent-tool-scoping-per-blueprint-section.spec.md` (sibling roadmap specs, read in full — each
  names a file this issue refreshes and plans a follow-up edit to it)
- `staging/sync-to-claude.sh` (PAIRS table extended by two lines) and `docs/RUNBOOK.md` (the bulk-copy disaster
  recovery procedure this ADR's PAIRS-scoping decision is reasoned against)
- `docs/vibe-coding-system.md` lines 2282 and 2297 (the two blueprint references this ADR reconciles)

---

## 1. Context

`staging/` plus `staging/sync-to-claude.sh` (ADR-0022) is the repo-tracked bridge to `~/.claude`, the directory
where the actual multi-agent system runs. ADR-0024 (issue #28) used that bridge for the first time at scale: it
vendored 90 previously-untracked deployed files into `staging/` and grew the PAIRS table from 15 to 105 entries,
but its own scope statement was explicit that a second, non-overlapping category of staleness existed and was
reserved for this issue: `staging/plugin/agents/` (8 files, staged before several agent-behavior ADRs shipped),
nine repo-native skills that were authored directly in the repo rather than vendored from a live deployment, and
`staging/user/` (global `CLAUDE.md`, path-scoped rules, `settings.json`). Reading the actual deployed tree
(`~/.claude`, authorized read-only for this feature) and diffing it against every file this issue's SPEC names
confirmed the staleness is real and, in most cases, extensive — not confined to the specific deltas SPEC calls out
as motivating examples:

- **All 8 agent files differ**, from 2 diff lines (`tester.md`) to 67 (`coder.md`). The staged `coder.md` has
  **zero** occurrences of `PATTERN` (the deployed copy has 8) — the ADR-0001/0004 classifier convention is not
  merely stale in staging, it is entirely absent. Four staged agents (`architect.md`, `debugger.md`,
  `refactorer.md`, `reviewer.md`) still instruct checking/appending `docs/agent-notes/<agent>.md`, the file-based
  memory mechanism ADR-0012 retired in favor of the orchestrator-mediated `DURABLE NOTES`/`PATTERN:` report
  convention this very agent's own instructions now use. Staged `architect.md` has zero occurrences of `DURABLE
  NOTES` (deployed has one) — the ADR-0014 output-block convention is likewise absent, not stale.
- **All 7 named repo-native `SKILL.md` files differ**, from 21 diff lines (`interview-driver`) to 288
  (`commit`, whose staged copy is missing the entire `--autopilot` flag documented in ADR-0020). Both
  `interview-driver` and `fastapi-react-vibe` staged copies still carry `disable-model-invocation: true`; **neither
  deployed copy does** — a fact with real weight, addressed directly in §2.1 and flagged in Consequences.
- **`protect-files.sh` and `auto-format.sh` differ** (12 and 8 diff lines): the deployed fail-open `jq` handling
  ADR-0024 already flagged as deliberate for these same two scripts is absent from the staged copies.
- **`staging/user/CLAUDE.md` (112 diff lines) and `staging/user/rules/swift.md` (19 diff lines) differ**;
  `staging/user/rules/parallelization.md` does not exist in staging at all, though it is a normal,
  already-`paths:`-scoped rules file deployed since 2026-05-19.
- **`staging/user/settings.json` diverges substantially**, not cosmetically: the deployed `permissions.deny` list
  has grown from the staged file's 4 entries to 13 (broader `rm`/`git reset --hard`/`git clean`/`git checkout --`/
  `git restore`/`git stash drop` coverage); `permissions.allow` replaced a bare `"mcp__*"` wildcard with an
  explicit ~25-entry narrowed set; the `hooks` block grew from 2 wired events to 6 (`PreToolUse`, `PostToolUse`,
  `SessionStart`, `SessionEnd`, `Stop`, `UserPromptSubmit`); `enabledPlugins` reflects a materially different
  plugin set than staged. This is the file `docs/RUNBOOK.md` Step 3 later `cp`s verbatim onto a new machine's
  `~/.claude/settings.json` after a HITL diff review — a stale staged copy would misrepresent the live permission
  and hook-wiring posture to a future reader or a future bootstrap.
- **`staging/plugin/skills/project-bootstrap/` still exists in staging** (`SKILL.md` only, no `scripts/`/`tests/`)
  but **no longer exists in deployment** (`ls ~/.claude/skills/project-bootstrap` — not found). Two blueprint
  prose locations still describe it as a skill to build: `docs/vibe-coding-system.md:2282` ("the 7 custom skills
  from sec. 8.3 ... project-bootstrap") and `:2297` (the sec. 15 installation checklist's skill list).
- **`staging/plugin/skills/{goal-loop,research-prompt}/SKILL.md` exist in staging only** — neither is deployed
  (`ls ~/.claude/skills/` has no `goal-loop` or `research-prompt` entries) and neither has a PAIRS entry, so today
  there is no way to push either one out via `sync-to-claude.sh --apply`.

Two structural facts, both discovered while planning rather than stated in SPEC, drive this ADR's PAIRS-scoping
and file-deletion decisions:

1. **`docs/RUNBOOK.md` documents a second, independent deploy mechanism.** Its Steps 2, 3, 4, 6, and 7 are a
   step-by-step, heavily HITL-gated **bulk** procedure — `cp staging/user/CLAUDE.md ~/.claude/CLAUDE.md`,
   `cp staging/user/settings.json ~/.claude/settings.json` (after a mandatory diff review), `cp
   staging/user/rules/*.md ~/.claude/rules/`, `cp staging/plugin/agents/*.md ~/.claude/agents/`, and `cp -R
   staging/plugin/skills/* ~/.claude/skills/` — meant for full disaster recovery or new-machine bootstrap, not
   day-to-day fix propagation. `sync-to-claude.sh`'s PAIRS table is the **other** mechanism: an incremental,
   dry-run-by-default, single-file sync meant for pushing one small fix out without re-running the whole bulk
   procedure. Every file this issue refreshes in `staging/plugin/agents/`, the 7 named skills, and `staging/user/`
   is already reachable through RUNBOOK's bulk `cp`/`cp -R` glob operations (Step 4's glob copy, in particular,
   already picks up the newly-added `parallelization.md` with no RUNBOOK edit required). This resolves why SPEC's
   objective 3 asks for PAIRS growth on exactly two files, not all nine repo-native skills — see §2.3.
2. **The staged `interview-driver`/`fastapi-react-vibe` `disable-model-invocation: true` flag is not stray
   staging drift to preserve; it is a flag the currently-deployed copies have already dropped**, and SPEC's own
   success criteria (`staged interview-driver has no disable-model-invocation`) directs mirroring that removal.
   The blueprint itself documents why the flag matters (`docs/vibe-coding-system.md:412`, the "loop taxonomy"
   changelog entry from 2026-07-09): a scheduled `/loop` fire executes any skill Claude is allowed to invoke on
   its own, and a skill missing this flag can fire unintentionally from an interval trigger. That the flag is
   gone from deployment is therefore a live, currently-real gap against the blueprint's own stated design — not
   a hypothetical one. Fixing it is explicitly out of this issue's scope (SPEC's objective 1 is mechanical
   mirroring; "fixing defects inside the refreshed files" is explicitly listed under **Out**), and no sibling
   spec (#30, #38, #39, #40 — all read in full) claims it either. This ADR records the finding and mirrors
   deployment as directed; see §2.1 and the Consequences/Negative section for why this is flagged rather than
   silently carried forward.

## 2. Decision

Refresh every file SPEC names to match its deployed counterpart exactly (full mirror, not selective patching),
rewrite `staging/user/settings.json` through one deterministic, reviewable transform rather than a hand edit,
grow PAIRS by exactly two entries, delete the retired skill, and reconcile precisely the two blueprint lines SPEC
names — nothing broader.

### 2.1 Refresh mechanism: byte-identical mirror via `cp -p`, no selective patching, no reconciliation toward blueprint intent

For the 8 agent files, the 7 named `SKILL.md` files, `protect-files.sh`, `auto-format.sh`, `staging/user/CLAUDE.md`,
and `staging/user/rules/swift.md`: `cp -p "$HOME/.claude/<path>" "staging/<path>"`, then verify with `diff -q`
(expect no output / exit 0). `-p` preserves the source's permission bits, carrying the executable bit on the two
scripts automatically. `staging/user/rules/parallelization.md` is a new file, copied the same way (`cp -p`, no
prior staged copy to overwrite). This is a full, unconditional mirror — including the deltas SPEC calls out by
name (`--autopilot` arriving in `commit`, `disable-model-invocation` leaving `interview-driver`/`fastapi-react-vibe`,
`PATTERN`/`DURABLE NOTES` arriving in the agents, `docs/agent-notes` leaving them) **and** deltas SPEC does not
name (`architect.md`'s `effort: max` vs. the blueprint's documented `xhigh`, `reviewer.md`'s extra `LSP` tool
grant, `architect.md`'s extra inline `mcp__plugin_context7_context7__*` tool grants). None of the undocumented
deltas are reconciled toward blueprint intent by this issue — SPEC's success criterion is byte-identity with
deployment, full stop, and issue #40 (read in full) is explicitly the one that decides, file by file, whether
each such drift is a defect to revert or a deliberate divergence to document. This issue supplies #40 its
starting material as-is.

### 2.2 `staging/user/settings.json`: one deterministic `jq del()` transform, verified structurally, not by raw diff

```bash
jq 'del(.model, .theme, .tui, .editorMode, .statusLine, .cleanupPeriodDays)' \
  "$HOME/.claude/settings.json" > staging/user/settings.json
```

This mirrors the entire live file — `hooks`, the grown `permissions.deny` list, the narrowed
`permissions.allow` (replacing the stale bare `"mcp__*"` entry), `enabledPlugins`, `attribution`, `worktree`,
`autoMode`, everything — and removes exactly the six keys SPEC names as machine-local, no more, no fewer. The
six are confirmed machine/session-local by cross-referencing `docs/RUNBOOK.md` Step 3, which `cp`s this file
verbatim onto a new machine after a human diff review: `model`, `theme`, `tui`, and `editorMode` are personal UI
preferences a new machine's owner sets for themselves; `statusLine` and `cleanupPeriodDays` are likewise
per-installation, not part of the blueprinted agent system. `jq`'s output is valid JSON, preserves the remaining
keys' insertion order (`del()` does not reorder), and is independently re-runnable — the transform is the
verification. Success is confirmed structurally (each of the six keys absent, `permissions.allow` contains the
narrowed `mcp__` entries and not a bare `"mcp__*"`, and a `diff` of `jq -S del(...)` on the deployed file against
`jq -S .` on the staged output is empty), not by requiring the staged file to be byte-identical to deployment —
it is deliberately not, by design, per SPEC's edge case note. This file carries no PAIRS entry, unchanged from
today: `sync-to-claude.sh`'s own trailing "MANUAL STEP" comment already states "The live settings.json is NOT
auto-edited," and `docs/RUNBOOK.md` Step 3 already provides its own, more heavily HITL-gated, direct-diff-then-`cp`
path for this specific file. Nothing about that mechanism changes here.

### 2.3 PAIRS grows by exactly two entries (`goal-loop`, `research-prompt`); the other 17 refreshed files get none

```
plugin/skills/goal-loop/SKILL.md|skills/goal-loop/SKILL.md
plugin/skills/research-prompt/SKILL.md|skills/research-prompt/SKILL.md
```

Appended after the existing last entry (`plugin/skills/find-skills/SKILL.md|skills/find-skills/SKILL.md`), before
the closing `"`. No existing line is reordered, edited, or removed — the same append-only discipline ADR-0024
established. `sync-to-claude.sh`'s dry run is expected to print `== NEW:` for both (they have no deployed
counterpart yet — this is the correct, intentional signal that a future human `--apply` will create them, not a
misconfigured `dst` path, which is what `== NEW:` signals for every other PAIRS entry in this table). The 8
agents, 7 named skills, and 2 scripts refreshed by this issue receive **no** new PAIRS entries: per §1's first
structural fact, all of them are already reachable through `docs/RUNBOOK.md`'s bulk `cp`/`cp -R` disaster-recovery
path, and SPEC's objective 3 asks for PAIRS growth on exactly `goal-loop` and `research-prompt` — the two files
that need the lightweight, single-file incremental path *right now* because they are new and ready to ship, not
part of a full redeploy. This is a deliberate scope line, not an oversight, and it has one concrete, named
consequence worth carrying forward explicitly: issue #39 (read in full) plans to edit
`claude-md-generator/SKILL.md`, one of the seven files this issue refreshes but does not add to PAIRS. After
this issue, that file still has no incremental deploy path — #39 will need to add its own PAIRS entry if it wants
one, or rely on RUNBOOK's bulk path. Flagged here so #39 does not assume an entry already exists.

### 2.4 `project-bootstrap`: delete the staging directory, reconcile exactly two blueprint lines, touch nothing else

`rm -rf staging/plugin/skills/project-bootstrap/` (a single `SKILL.md`, no `scripts/`/`tests/`/`references/` —
confirmed by directory listing before deletion). In `docs/vibe-coding-system.md`:

- Line 2282: `"the 7 custom skills from sec. 8.3"` → `"the 6 custom skills from sec. 8.3"`; drop `, project-bootstrap`
  from the parenthetical list (both the count and the name change together — leaving a stale count next to a
  corrected list would be a new, self-inflicted inconsistency).
- Line 2297: drop `` `project-bootstrap` `` from the sec. 15 installation checklist's parenthetical skill list.
  No count to correct on this line (it is a bare list, not a "the N skills" sentence).

One new "Changes from previous versions" block is added (`### Correction 2026-07-11 (project-bootstrap retired
from staging)`), inserted immediately after the current most-recent entry (`### Audit 2026-07-09 (loop taxonomy:
/loop, /schedule, Routines)`, ending at line 421) and before the next one (`### Update 2026-06-23 (workflow model
pinning)`, starting at line 423) — matching the document's established convention of appending each new
correction directly after whichever entry is currently most recent, rather than at the very top or bottom of the
"Changes from previous versions" section. Full text specified in the implementation plan.

Deliberately **not** touched, and stated here so it is not later mistaken for an omission: section 8.3's per-skill
design catalog (`~line 1650`, a `project-bootstrap` frontmatter/body example — historically accurate design
documentation, not a live-status claim), section 8.6's "Deployed custom skills (active as of 2026-06)" table
(already correctly omits `project-bootstrap` — nothing to fix), the section 4 global-`CLAUDE.md` *template*
(`~line 970`, illustrative content, not this system's live configuration), and every mention of `project-bootstrap`
outside `docs/vibe-coding-system.md` (`docs/RUNBOOK.md`, `docs/GUIDA-CREARE-PROGETTO.md`,
`docs/guida-workflow-orchestrazione.md`, and the dated historical files under `docs/superpowers/plans/` and
`docs/superpowers/specs/`). SPEC's objective 2 says "reconcile its **two** blueprint references," and its edge
case section repeats the same figure — this ADR treats that as an exact, deliberate scope boundary, not a
lower bound.

### 2.5 Task sequencing: one task per SPEC scope bullet, shared regression checkpoint after each

Eight tasks, one per SPEC "In" bullet plus a closing verification/report task, each ending in the same two-part
checkpoint used throughout: the existing 5-file test suite (`phase1`, `prep`, `hook-probe`, `hook-verify-workflow`,
`pairs-completeness`) stays green, and `pairs-completeness.test.sh` reports the expected count for that point in
the plan (105 through the settings.json task, 107 from the PAIRS task onward). No new test script is authored by
this plan — unlike ADR-0024, which had to build `pairs-completeness.test.sh` from nothing, this issue's only
structural change (two PAIRS lines) is already covered by that existing checker, and the settings.json transform
is verified inline via `jq` assertions specified in the plan, not a new persisted harness.

## 3. Alternatives considered

### 3.1 Refresh mechanism for agents/skills/scripts/user-config

**Chosen:** full byte-identical mirror via `cp -p`, unconditionally, including undocumented drift (§2.1).

- **Alternative A — selective line patching, touching only the specific deltas SPEC names by example** (add
  `--autopilot` to `commit`, add `PATTERN` support to `coder.md`, etc., leaving everything else in each file
  untouched). Rejected. SPEC's success criterion is explicit and absolute: "Zero diff between each refreshed
  staged file and its deployed counterpart" — a partial patch cannot satisfy that criterion by construction.
  It would also silently leave every *undiscovered* delta in place (the `LSP` tool grant on `reviewer.md`, the
  extra `mcp__` grants on `architect.md`, the `effort: max` divergence) — precisely the class of staleness this
  issue exists to close, and precisely the material issue #40 needs already surfaced in staging to do its job.
- **Alternative B — reconcile toward blueprint intent while refreshing** (e.g., keep `disable-model-invocation`
  on `interview-driver`/`fastapi-react-vibe` even though deployment dropped it, revert `architect.md`'s effort
  pin to the blueprint's `xhigh`, strip `reviewer.md`'s extra `LSP` grant). Rejected. This is explicitly out of
  scope per SPEC ("Out: Fixing defects inside the refreshed files (later roadmap issues)") and is, item for item,
  issue #40's stated mandate for the three agent files it names. Doing it here would also require this issue to
  adjudicate a judgment call (is a given drift a defect or a deliberate, undocumented improvement?) that #40's own
  SPEC frames as needing "an ADR-recorded deliberate divergence with a compensating control" — a decision-making
  process this mechanical refresh issue has no basis to short-circuit.

### 3.2 PAIRS growth scope

**Chosen:** exactly two new entries, `goal-loop` and `research-prompt` (§2.3).

- **Alternative A — add PAIRS entries for all nine repo-native skills** (the seven named `SKILL.md` files plus
  `goal-loop`/`research-prompt`), on the theory that every skill with a staging copy should have an incremental
  deploy path for consistency with the 105 entries ADR-0024 already added. Rejected. SPEC's objective 3 names
  exactly two files ("Extend sync PAIRS so `goal-loop` and `research-prompt` can reach deployment"); the seven
  others are already reachable via `docs/RUNBOOK.md`'s bulk copy (§1, structural fact 1), so adding PAIRS entries
  for them is not blocked by any missing capability, only unrequested by this issue's SPEC. Widening PAIRS beyond
  what SPEC names is exactly the kind of scope decision ADR-0024 (§3.2) already flagged as deserving its own
  reviewed change, not a side effect of a refresh pass — and it would need its own answer for whether a future
  fix landing in one of these seven files (issue #39, concretely, for `claude-md-generator`) should sync via
  PAIRS or continue relying on RUNBOOK, a design question this issue is not positioned to answer for all seven at
  once.
- **Alternative B — add no PAIRS entries at all, treat `goal-loop`/`research-prompt` the same as the other seven.**
  Rejected. SPEC's objective 3 is explicit and named as one of this issue's three top-level objectives, not a
  side note; skipping it would leave two already-authored, ready-to-ship skills with no deploy path at all (not
  even RUNBOOK's bulk path helps until they are deployed once, which is exactly what a PAIRS-driven `--apply`
  would do). There is also a real difference in kind from the other seven: `goal-loop`/`research-prompt` have
  never been deployed, so RUNBOOK's bulk-copy Step 7 has never actually delivered them; the seven repo-native
  skills refreshed by this issue, by contrast, are already live in deployment and were only stale in staging.

### 3.3 `staging/user/settings.json` transform

**Chosen:** a single `jq del()` command against the six SPEC-named keys, verified structurally, kept outside
PAIRS (§2.2).

- **Alternative A — add `user/settings.json` to the PAIRS table.** Rejected. `sync-to-claude.sh`'s own header
  comment is explicit that this file is deliberately excluded from automatic sync ("The live settings.json is NOT
  auto-edited; the script prints the hook wiring to add by hand"), and `docs/RUNBOOK.md` Step 3 already has a
  dedicated, more heavily HITL-gated mechanism for it (mandatory diff review before `cp`) — appropriate given a
  `settings.json` change alters live permission and hook-wiring posture, a materially higher blast radius than a
  skill or script content change. Folding it into PAIRS's lighter per-file dry-run/apply flow would downgrade that
  ceremony, not preserve it.
- **Alternative B — hand-edit the file key by key, preserving the current staged file's structure and only
  touching the specific deltas.** Rejected in favor of the deterministic transform for the same reason ADR-0024
  preferred `cp -p` to a hand-authored patch: a ~150-key JSON file edited by hand risks transcription drift
  (a missed hook entry, a wrong deny-list line, silent reordering) that a reviewer cannot easily catch by eye,
  whereas `jq del()` against the live file is trivially re-runnable and its correctness is checkable by construction
  (diff the transform's output against a `jq`-computed expectation, as done during this ADR's own verification).
- **Alternative C — also strip additional keys that look machine-specific but are not named by SPEC** (e.g.
  `env.ANTHROPIC_DEFAULT_OPUS_MODEL`, `fallbackModel`, `availableModels`, all of which reference specific model
  identifiers). Rejected. SPEC's exclusion list is explicit and, read together with its edge-case note, exhaustive
  ("documented exclusions (model, theme, tui, editorMode, statusLine, cleanupPeriodDays)"). Silently dropping more
  than what SPEC names is the same category of unrequested scope expansion as Alternative A in §3.2, just in the
  opposite direction (removing content instead of adding a sync path) — a future issue can revisit which keys
  belong in the reference copy with its own review, not as a side effect of this one's mechanical refresh.

### 3.4 `project-bootstrap` retirement scope

**Chosen:** delete the staging directory; reconcile exactly `docs/vibe-coding-system.md` lines 2282 and 2297
(§2.4).

- **Alternative A — scrub every `project-bootstrap` mention repository-wide** (section 8.3's design catalog,
  section 4's template, `docs/RUNBOOK.md`, `docs/GUIDA-CREARE-PROGETTO.md`, `docs/guida-workflow-orchestrazione.md`,
  and the dated historical plan/spec files under `docs/superpowers/`). Rejected. SPEC's objective 2 states "two
  blueprint references" verbatim, and its success criteria repeat the same figure — treating that as a floor
  rather than an exact target would be undirected scope creep, the same failure mode ADR-0024 (§3.2, Alternative)
  explicitly rejected for PAIRS restructuring. Several of the un-scrubbed mentions are not stale claims at all:
  section 8.3 documents what was designed (historically accurate), the dated `docs/superpowers/plans/` and
  `docs/superpowers/specs/` files are historical records that should never be rewritten after the fact, and
  section 8.6's active-skills table already omits `project-bootstrap` correctly. `docs/RUNBOOK.md` and the two
  `GUIDA-*`/workflow guide files are not named anywhere in SPEC's scope; editing them here would be a second,
  unrequested feature bundled into a refresh issue.
- **Alternative B — leave the staging directory in place and only fix the two blueprint lines**, on the theory
  that the SKILL.md content itself is harmless if never synced out. Rejected. `docs/RUNBOOK.md` Step 7 performs
  `cp -R staging/plugin/skills/* ~/.claude/skills/` — an unconditional bulk copy of every directory under
  `staging/plugin/skills/`. Leaving a stale `project-bootstrap/` in staging means the very next full
  disaster-recovery restore silently **resurrects a skill that deployment has already retired**, contradicting
  the blueprint text this same task is correcting in the same commit. Deleting the directory is not cosmetic; it
  is required for the two blueprint edits to describe reality accurately after a future restore, not just today.

### 3.5 Handling the `disable-model-invocation` finding on `interview-driver`/`fastapi-react-vibe`

**Chosen:** mirror deployment (flag removed from both staged copies, per SPEC's explicit success criterion),
document the finding in this ADR, and flag it as an unowned risk for human attention rather than act on it here
(§1, fact 2).

- **Alternative — treat the blueprint's documented `/loop` safety design (`docs/vibe-coding-system.md:412`) as
  authoritative over SPEC's literal success criterion, and keep the flag in the refreshed staged copies even
  though deployment has dropped it.** Rejected, for the same reason as §3.1's Alternative B: SPEC's objective 1
  and success criteria are explicit and unambiguous ("staged interview-driver has no `disable-model-invocation`"),
  "fixing defects inside the refreshed files" is explicitly out of scope, and no roadmap issue read while planning
  this one (SPEC.md itself, or #30/#38/#39/#40) claims ownership of this specific gap. An architect issuing a
  unilateral, silent divergence from an explicit, machine-generated (Phase P / ADR-0023) success criterion — on a
  file this issue's own SPEC lists as in-scope for mirroring — is a worse outcome than surfacing the concern
  loudly in the deliverable and letting a human decide whether it needs its own backlog issue. The finding is
  real either way; only the party who acts on it changes.

## 4. Consequences

### Positive

- Closes the second half of audit finding cluster 3.38's staleness problem (ADR-0024 closed the "missing
  entirely" half; this closes the "present but stale" half) across the specific findings SPEC cites (1.5,
  2.21–2.26, 3.33–3.37, 3.39): 19 existing files refreshed to byte-identity with deployment, 1 new file added
  (`parallelization.md`), 1 file transformed under a documented, re-runnable rule (`settings.json`), 1 retired
  file removed, 2 new PAIRS entries, 2 blueprint lines corrected. `staging/` now reflects what is actually
  running, not a  snapshot from before ADR-0001/0004/0012/0014/0015/0020 shipped.
- Directly unblocks the sibling roadmap issues that name files this issue refreshes: #38 (hooks, unaffected by
  this issue but sequenced after #28 as this ADR's Related section notes), #39 (five skills, one of which —
  `claude-md-generator` — is refreshed here), and #40 (`architect.md`, `reviewer.md`, `researcher.md`, refreshed
  here with their real, current, undocumented drift intact and ready for #40 to adjudicate). None of the three
  has to first discover that its target file is stale before it can start.
- `docs/RUNBOOK.md`'s Step 7 bulk disaster-recovery restore no longer risks resurrecting a retired skill
  (`project-bootstrap`), and its Step 3 settings.json restore path now diffs against a staged reference that
  actually reflects the current hook wiring, deny-list breadth, and plugin set, rather than a materially
  out-of-date approximation.
- The finding that `interview-driver`/`fastapi-react-vibe` have lost `disable-model-invocation: true` in
  deployment — a live gap against the blueprint's own documented `/loop` safety design — is now written down in
  a reviewed artifact (this ADR) for the first time, rather than existing only as an undetected divergence between
  two trees nobody was diffing.
- No new test infrastructure was required: the existing 5-file suite and `pairs-completeness.test.sh`
  (ADR-0024) fully cover this issue's one structural change (PAIRS growth); the settings.json transform is
  verified by construction (`jq` assertions specified in the implementation plan), keeping this issue's footprint
  proportionate to a refresh rather than a new feature.

### Negative

- The `interview-driver`/`fastapi-react-vibe` `disable-model-invocation` gap (§1, fact 2; §3.5) is documented but
  **not fixed** by this issue, and is not currently owned by any other named roadmap issue either. It is a real,
  live gap against the blueprint's own stated design, and it will remain live in both deployment and (after this
  refresh) staging until a human opens a dedicated fix, which this ADR recommends but cannot itself schedule.
- The seven repo-native skills refreshed here (`commit`, `interview-driver`, `adr-writer`, `claude-md-generator`,
  `code-review-checklist`, `swift-vibe`, `fastapi-react-vibe`) still have no PAIRS entry after this issue (§2.3).
  Issue #39, which already plans to edit `claude-md-generator/SKILL.md`, will need to add its own PAIRS entry (or
  explicitly accept RUNBOOK-only deployment) — this issue does not do it preemptively, so the gap is real, if
  narrow and already flagged for the one issue that will hit it first.
- Several undocumented drifts propagate into staging unresolved by design (§2.1): `architect.md`'s `effort: max`
  vs. blueprint's `xhigh`, `reviewer.md`'s extra `LSP` tool grant, `architect.md`'s extra inline `mcp__` tool
  grants. This is intentional (issue #40's job), but it does mean staging is, for a short window between this
  issue and #40, an accurate mirror of a deployment that itself has undocumented drift from the blueprint — a
  correct state for this issue's purposes, but one a reader diffing staging against the blueprint text alone
  (rather than against #40's forthcoming ADR) could misread as a staging bug.
- `docs/RUNBOOK.md` carries its own smaller, pre-existing staleness this issue does not touch: Step 4's comment
  listing expected rules files does not mention `parallelization.md` (already true before this issue, and now
  slightly more visibly incomplete once the file exists in staging too, even though the actual `cp
  staging/user/rules/*.md` command is glob-based and unaffected); Step 7's "7 folders" and Step 8's "7 custom
  skills" comments have been stale since ADR-0024 grew `staging/plugin/skills/` well past seven directories.
  Neither is named in this issue's SPEC scope, so neither is corrected here; both are worth a small follow-up.
- The settings.json transform, while deterministic, means the staged reference file will need re-running (not
  just re-diffing) every time it is refreshed in the future — a future maintainer must know to reach for the
  `jq del()` command in §2.2 rather than a plain `cp`, or they will reintroduce the six machine-local keys.

### Neutral

- `staging/plugin/skills/vibe-status/`'s pre-existing split between ADR-0021 artifacts and ADR-0024-vendored
  files (documented in ADR-0024 §4/Negative) is untouched by this issue — `vibe-status` is not in this issue's
  scope at all.
- This issue makes no change to how any hook is wired (`settings.json`'s hook entries are mirrored verbatim from
  deployment, not redesigned) and no change to `sync-to-claude.sh`'s copy/diff logic (only its PAIRS data grows,
  consistent with the frozen dry-run/apply contract ADR-0024 already established).
- `pairs-completeness.test.sh`'s structural-only design (ADR-0024 §3.4 — asserts every PAIRS `src` exists, never
  asserts byte-identity against `~/.claude`) is exactly why it needs no modification here: it validates the two
  new `goal-loop`/`research-prompt` lines the same way it validates the other 105, with no risk of the false
  failures a deployed-comparison test would have produced the moment this issue intentionally left `goal-loop`
  and `research-prompt` ahead of their own (still nonexistent) deployment.
- Whether any of the five newly-touched skills/agents/user files need a markdownlint ignore entry is not a
  decision this ADR has to make: the seven `SKILL.md` refreshes land under `staging/plugin/skills/`, already
  covered by the `.markdownlint-cli2.jsonc` ignore ADR-0024 added; `staging/user/CLAUDE.md`,
  `staging/user/rules/swift.md`, and the new `staging/user/rules/parallelization.md` are not covered by that
  ignore and are expected to pass lint as-is (verified during implementation, not assumed here).

## 5. References

- `SPEC.md` (repo root) / `docs/specs/29-refresh-stale-staging-copies-from-the-de.spec.md` — this issue's spec
- `docs/specs/38-hook-hardening-enum-value-lock-ownership.spec.md`,
  `docs/specs/39-skill-text-corrections-across-five-stand.spec.md`,
  `docs/specs/40-agent-tool-scoping-per-blueprint-section.spec.md` — sibling specs confirming forward dependencies
- `docs/architecture/ADR-0022-nightly-autopilot-goal.md` — `staging/` + `sync-to-claude.sh` + PAIRS mechanism,
  and the `docs/RUNBOOK.md` bulk-deploy procedure referenced throughout this ADR
- `docs/architecture/ADR-0024-28-vendor-deployed-only-skills-and-hooks.md` — the immediately preceding issue,
  established the PAIRS append-only discipline and `pairs-completeness.test.sh` this ADR reuses unmodified
- `docs/architecture/ADR-0001-coder-preflight-pattern-classifier.md`,
  `docs/architecture/ADR-0004-pre-flight-pattern-enforce-hook.md` — the `PATTERN:` convention this refresh
  restores to `staging/plugin/agents/coder.md`
- `docs/architecture/ADR-0012-agent-memory-orchestrator-mediated.md` — the memory convention that retired
  `docs/agent-notes/<agent>.md`, still referenced by four staged agent files before this refresh
- `docs/architecture/ADR-0014-architect-proposes-test-cmd.md` — the architect output-block convention this
  refresh restores to `staging/plugin/agents/architect.md`
- `docs/architecture/ADR-0020-autopilot-build-skill.md` — introduced `commit`'s `--autopilot` flag, absent from
  the staged copy before this refresh
- `staging/sync-to-claude.sh` — the file gaining two PAIRS lines
- `docs/RUNBOOK.md` (Steps 2–4, 6–7) — the bulk disaster-recovery mechanism this ADR's PAIRS-scoping decision
  (§2.3) is reasoned against
- `docs/vibe-coding-system.md` lines 2282, 2297, and the "Changes from previous versions" section (~line 10–500)
  — the blueprint prose corrected by this issue
- `.markdownlint-cli2.jsonc` — confirms the existing `staging/plugin/skills` ignore already covers this issue's
  `SKILL.md` refreshes
- Implementation plan: `docs/superpowers/plans/2026-07-11-29-refresh-stale-staging-copies.md`
