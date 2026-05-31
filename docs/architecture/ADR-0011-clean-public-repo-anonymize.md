# ADR-0011 — clean-public-repo + anonymous mode in the chain (tool contribution anonymization for public repos)

**Status:** Accepted  
**Date:** 2026-05-23  
**Author:** istefox  
**Supersedes:** none  
**Superseded by:** none  
**Related:** ADR-0003 (concept-to-code chain — the chain where the activation gate is inserted),
ADR-0008 (workflow v2 brainstorm — precedent of optional gate + non-terminal skill invoked by
the chain; schema 1.0->1.1), ADR-0010 (web-e2e-test — immediate preceding precedent of the
pattern "standalone skill + chain gate that invokes it", schema 1.1->1.2, fail-safe detection,
honest harness on non-headless feature), ADR-0009 (db-backup-guardrail — asymmetric fail-mode,
HITL gate on destructive operation, freshness via backup), ADR-0005 (vibe-status — standalone
skill with report).

---

## Context

A repo published on GitHub is often judged also by the markers of the tool it was written with
(commit trailers, trace comments, slop files, decorative strings/emoji). The purpose of the
feature, **binding and declared in the SPEC**, is dual: (1) **not advertise the tool** and
(2) **holistic quality** of the repo (essential commits, concise docs, zero useless files), so
that the work is judged by the code. The work remains the user's: they direct it, review it,
test it, and are responsible for it.

The user chose (BRAINSTORM, Alternative C*+D*) a **hybrid architecture**:
- **Prevention** on new repos -> an **anonymous mode** in the `concept-to-code` chain
  produces already-compliant output (clean commits/docs from the start, zero rewrite).
- **Remedy** on existing repos -> a **standalone `clean-public-repo` skill** that does audit
  + retroactive cleanup (e.g. already published Obsidian plugin).
- For **already-public** repos, default = **fresh-history publish** (derived repo with clean
  history; the original with traces remains private); **surgical in-place rewrite** remains
  an explicit second-choice option, never the default. Priority #1: **no unprotected
  destructive rewrite**.

This ADR designs: where to insert the activation gate in the chain, the form and dependencies
of the skill, detection, report contract, fresh-history flow, protected surgical rewrite,
coexistence of anonymous mode with `coder.md`/`architect.md`, and fail-modes of each
destructive operation.

### Ethical framing (constraint, not option)

Stated explicitly because it is a design boundary, not a detail: the purpose is **not to
advertise the tool + quality**. It is NOT: falsifying authors (never attributing commits to
real people who did not contribute) nor actively lying if someone explicitly asks. Native
attribution is already disabled (`settings.json: attribution {commit:"", pr:""}` — fact
verified in SPEC §"Ethical framing"). The feature removes **tool markers**, not falsifies
**human authorship**: the anonymous commit remains correctly attributed to the configured git
author (Stefano), not to an invented third party.

### Verified facts

- **`git-filter-repo` PRESENT** on the environment (`/opt/homebrew/bin/git-filter-repo`,
  version confirmed via `git filter-repo --version`). It is the de-facto standard for surgical
  rewrite (researcher report); `git filter-branch` is DEPRECATED and must not be used; BFG is
  not suitable for arbitrary text replacement. Supports `--replace-text` (regex),
  `--message-callback`, `--dry-run`; rejects non-fresh-clone repos by default.
- **`gitleaks` ABSENT** on the environment (`command -v gitleaks` -> empty). -> The skill
  **cannot depend** on gitleaks; it must degrade with custom grep (see D3).
- **`git` PRESENT** (`/usr/bin/git`).
- **Live manifest schema = `1.0|1.1`** (`manifest-validate.sh` line 29:
  `^manifest_schema_version: "(1\.0|1\.1)"$`; `VALID_STEPS` lines 57-72). Schema 1.1 is
  retrocompat 1.0. Precedent for retrocompat bump: ADR-0008 (1.0->1.1), ADR-0010 (1.1->1.2
  — see coexistence note in D1).
- **`concept-to-code` chain**: 16 states; Gate 0 is a *check* in `step_0_init` (not a state);
  Gates 1/1b/2/3/4/5 exist. `coder.md` has NO "anonymous mode" rule; it drafts a Conventional
  Commit for the orchestrator (line 23/76) but never commits.
- **Live harness baselines** (run 2026-05-23): review-triage-fix **60**, concept-to-code
  **20**, design-brainstorm 9, refactor-snapshot 18, vibe-status 10,
  pre-flight-pattern-enforce 13, run-hook-tests 24, db-backup-guardrail 16. All `FAIL=0`.

### Explicit assumptions (NOT validated — the feature rests on these)

- **Complete detection of the public remote requires an authenticated API call**
  (`gh repo view --json visibility`). Without `gh` or without auth, the visibility of a GitHub
  remote **is not reliably determinable** from the URL alone (a `https://github.com/...` URL
  can point to a private repo). -> Fail-safe decision in D1: if visibility is not determinable,
  do NOT propose the gate (silent), to avoid disturbing on private repos.
- **The effectiveness of cleanup on a real UI/history (rewrite, fresh-history publish,
  force-push)** is not deterministically testable headless: it requires a real repo with remote.
  The harness covers only the pure parts (detection, classification, dry-run on local fixture);
  the rest remains an open question validatable only in a pilot (honesty as ADR-0008/0009/0010).
- The repo `vibe-coding-system` is NON-git: the deliverables of this ADR are the 3 markdowns
  (ADR + plan + eventual ARCH). The deploy of the live artifacts
  (`~/.claude/skills/clean-public-repo/`, chain patch) is a separate task (TDD plan),
  **without commit step**.

---

## Decision

Adopt the **hybrid architecture C* + D*** from the BRAINSTORM:

1. **Anonymous mode in the chain** (prevention): a flag `anonymize: true` in the manifest
   (schema **1.2**, retrocompat 1.0/1.1) influences the **dispatch templates** of
   architect/coder and the gate summaries. Activated by a **dedicated "Gate 0b — anonymize"
   gate**, conditional, after Gate 0 and before Step 1.
2. **Standalone `clean-public-repo` skill** (remedy): audit + cleanup of a new or existing repo.
   **Hybrid action** (signals -> removes only on confirmation). Strategies for history:
   **fresh-history publish (default for already-public)** and **surgical rewrite (option 2,
   never default)**. Detection via **custom grep** (set of tool markers) with gitleaks as
   **optional integration** if present.
3. **Reuse, not duplication:** the chain contains NO cleanup logic; for existing repos it
   redirects to the skill (single source of truth, pattern Gate 1b->design-brainstorm,
   Step 6->review-triage-fix, Gate 6->web-e2e-test — 4th instance).

Below is the decision for each of the 8 architectural questions.

### D1 — Where to insert the gate: **dedicated Gate 0b**, auto-detect via `gh` with fail-safe, `anonymize` flag in manifest

**Dedicated gate "Gate 0b — anonymize"**, NOT an extension of Gate 0. Rationale: Gate 0 has
precise and orthogonal semantics (chain-vs-lightweight triage); overloading it with anonymity
mixes two independent decisions and makes the two checks separately undeactivatable. Gate 0b is
a conditional check in `step_0_init` (like Gate 0 — it is not a state machine state), executed
**after** Gate 0 (`[c] chain`) and **before** the transition to `step_1_interview`.

**Auto-detect of public remote** (cascade, helper `scripts/detect-public-remote.sh`):
1. `git rev-parse --is-inside-work-tree` -> if non-git -> **silent** (no gate). Safe default.
2. `git remote get-url origin` (and other remotes) -> if no remote -> **silent**.
3. Host = `github.com` (or `git@github.com:`)? If no (GitLab/Bitbucket/private host) -> **silent**
   (SPEC R1 scope is GitHub; extensible in the future).
4. Visibility: if `gh` is present and authenticated ->
   `gh repo view <owner/repo> --json visibility -q .visibility`. `PUBLIC` -> propose gate.
   `PRIVATE`/`INTERNAL` -> **silent**.
5. If `gh` absent or not authenticated -> **visibility not determinable** -> **silent**
   (fail-safe towards "do not propose": better not to disturb on a private repo than to expose
   the mode on a repo that is not public). SPEC R1 says "silent on private/local": indeterminate
   is treated as "non-public" to not violate that guarantee.

The mode remains a **user decision** (`[y/n]`), never auto-applied (SPEC R1).

**Flag form:** `anonymize: true|false` in the manifest (schema **1.2**), default `false`.
Influences **dispatch templates** (D7), not the agent SKILL.md. It is a chain state data item,
consistent with `mode`/`gate0`/`brainstorm` already in the manifest.

### D2 — Form of `clean-public-repo`: **standalone skill + bash 3.2 scripts**, optional external dependencies with graceful degrade

**Standalone skill** `~/.claude/skills/clean-public-repo/` (procedural orchestrator SKILL.md
+ `scripts/` bash 3.2-clean + `tests/run-tests.sh`). Callable on demand (SPEC R6) and
**reused** by the chain only as a *recommendation* (the chain does not do retroactive cleanup
— see D7). Subject = **orchestrator**: destructive git operations require interactive HITL;
a sub-agent in auto mode must not be able to execute them (consistent ADR-0010 D1, ADR-0009).

**External dependencies and absence handling (HARD constraint — verified: gitleaks absent):**

| Dependency | Use | If ABSENT |
|---|---|---|
| `git` | core (always) | the skill cannot operate on a history -> degrades to audit of working-tree files only + commit messages via `git log` if present; if completely absent, declares "non-git" and terminates without error (SPEC edge "detached branch / non-git -> degrades without errors"). |
| `git-filter-repo` | surgical rewrite (option 2) | **present** on the environment, but the skill **always verifies** `command -v git-filter-repo`. If absent -> surgical rewrite strategy **disabled** with install message (`brew install git-filter-repo` or `pip3 install git-filter-repo`); fresh-history publish (which uses only core `git`) remains available. |
| `gitleaks` | bonus secret detection + string cross-check | **absent** on the environment. The skill works **without** gitleaks (custom grep is the primary detection — D3). If present, uses it as **optional integration** (generates custom `.gitleaks.toml` + parses JSON) and notes it in the report; if absent -> no error, note "gitleaks not installed: lexical detection via grep (secret-scanning bonus unavailable; install: `brew install gitleaks`)". |
| `gh` | remote visibility detection (D1) + possible derived repo creation (D5) | if absent/not auth -> D1 silent; D5 degrades to manual instructions (user creates repo on GitHub and provides the URL). |

Principle: **an absent dependency never blocks the minimal path** (custom grep + fresh-history
via core git). Dependencies improve coverage, they do not enable it.

### D3 — Detection: **custom grep (primary) on SPEC R3 marker set** + optional gitleaks; report with coverage and LIMITATIONS

**Lexical detection via custom grep** as primary engine (zero-dep, bash 3.2-clean,
stack-agnostic). Pattern set derived from SPEC R3, on two surfaces:

- **Working tree (tracked files):** `git ls-files` -> for each text file, grep of patterns:
  - Commit trailers/markers remaining in files: `Co-Authored-By: Claude`, `Generated with Claude Code`.
  - Trace comments: `// added by Claude`, `# generated by`, task/AI references, clearly generated
    TODOs (conservative patterns, see false positives below).
  - `claude` / `AI` strings + unrequested decorative emoji (emoji range + keyword).
  - Slop / useless files: heuristic on names (`scratch`, `notes`, `*-COPY`, redundant READMEs) ->
    **signaled, never removed by default** (R2).
- **Commit history (messages):** `git log --format=%B` -> same trailer/marker patterns.

**Optional gitleaks:** if present, a custom `.gitleaks.toml` is generated with rules for tool
markers (beyond native secret rules), JSON output parsed and **merged** into the grep report.
It is a cross-check + the bonus secret-scanning (noted as future in SPEC, here only if gitleaks
is present). **Never a requirement.**

**False positives (SPEC edge):** legitimate dependencies (`claude-*` as package name), `AI` in
a domain/proper name. -> Detection **signals with context** (path:line + match), does not remove
(R2). Removal is always per-category/element confirmation.

**Coverage and LIMITATIONS in report (requirement emerged in BRAINSTORM, binding):** the report
MUST explicitly declare what it does **NOT** cover, to avoid a false sense of security: binaries,
images, generated/minified files, git metadata (author/committer date already OK because we do
not falsify authors), non-lexical semantic traces (writing style), content in non-tracked /
`.gitignore`d files. See D4.

### D4 — Report contract (hybrid action): markdown `docs/clean-report/<date>-<topic>.md`, R3 categories, mandatory COVERAGE/LIMITATIONS section

The skill writes **a report** in `<project-root>/docs/clean-report/YYYY-MM-DD-<slug>.md`
(creates the dir if absent). Structure (English headings, Italian prose — consistent with the
system):

- **Header:** date, repo path, remote+visibility (or "not determinable"), proposed history
  strategy (fresh-history publish | surgical rewrite | none), audit outcome
  (`ready` | `to-clean`).
- **Findings per R3 category:** for each (commit trailers, trace comments, slop/inflated docs,
  claude/AI+emoji strings, other residue) -> list `path:line — match — category`, and for
  commits `<short-sha> — message line`. Each finding marked `auto-removable` (safe textual
  removal) | `review-needed` (possible false positive: dependency/name) | `manual` (slop file:
  human decision).
- **History strategy (if traces exist in commits):** recommendation fresh-history (default if
  already-public) vs surgical rewrite (option 2), with safety requirements (D6).
- **COVERAGE & LIMITATIONS (mandatory section):** what was scanned (tracked text files + commit
  messages) and **what was NOT** (binaries, generated, metadata, semantic traces, non-tracked
  files). Explicit declaration: "this audit reduces known lexical markers; does NOT guarantee
  total indistinguishability and does NOT replace human review".
- **Proposed actions:** confirmable list per category (`[y]` remove auto-removable / `[s]` skip
  / per-element detail). **No blind removal** (R2).

Outcome `ready` when zero `auto-removable` residual findings after confirmed cleanup (SPEC DoD).

### D5 — Fresh-history publish (default for already-public): derived public repo, original history private

Flow (helper `scripts/fresh-history-publish.sh` — guide + dry-run; mutating actions behind HITL):
1. **Mandatory backup** of `.git/` original: `tar -czf .git-backup-<ts>.tar.gz .git`
   (researcher best practice; SPEC R5). Never proceed without it.
2. **Working tree cleanup** on confirmed `auto-removable` findings (D4) -> clean commit
   on the current branch (NOT yet published).
3. **Orphan branch:** `git checkout --orphan public-clean` -> `git add -A` ->
   a single curated commit (`git commit`), essential message (anonymous mode D7). The
   development history (with traces) **remains intact** on the original branch, **private**.
4. **Derived publication:** preferably as a **new public repo** (the user creates it on GitHub;
   if `gh` is present and authorized, `gh repo create` on confirmation) with a dedicated remote;
   push of only `public-clean`. **No force-push on the original repo** -> no suspicious gap,
   no corruption risk (BRAINSTORM Alternative D, TOP risk mitigated).
5. The original private history is never destructively touched.

Default for **already-public** repos because it avoids force-push entirely (the riskiest action).

### D6 — Surgical rewrite (option 2, never default): `git-filter-repo` with fresh clone + tar backup + dry-run + HITL before force-push

Only as an **explicit second choice** (the user requests it deliberately), for the case
"existing not-yet-public" or when one wants to preserve historical granularity. Flow (helper
`scripts/surgical-rewrite.sh` — safety orchestrator, never automatic):
1. **Fresh-clone precondition:** `git-filter-repo` by default rejects a non-fresh-clone repo;
   the skill respects this and **instructs** the user to operate on a fresh clone (never on the
   working repo). Does not pass `--force` to bypass the protection.
2. **Mandatory tar backup** of `.git/` before any operation (SPEC R5; researcher).
3. **Always dry-run first:** `git filter-repo --replace-text <patterns> --dry-run` (+
   `--message-callback` for trailers) -> shows what would change (SPEC R5: "dry-run shows what
   would change").
4. **Automatic backup of branches/tags** before application (SPEC R5).
5. **Apply** the rewrite on the clone.
6. **Force-push ONLY after explicit HITL** (`AskUserQuestion` / confirmation box): it is a
   destructive remote operation (breaks clones/forks). **Never automatic, never from sub-agent.**
   Consistent with `db-backup-guardrail` (ADR-0009): an irreversible operation is behind a human
   gate.

The SKILL.md declares that surgical rewrite is opt-in and that fresh-history is the default for
already-public.

### D7 — Anonymous mode in the chain: via **dispatch templates** (no patch to coder.md/architect.md), coexistence with existing coder rule

When `manifest.anonymize=true`, the chain **extends dispatch prompt-templates** (does NOT modify
agent SKILL.md — same pattern as the additive directive of `claude-md-generator`, concept-to-code
§3 Step 3). Concretely:

- **Coder dispatch (Step 5):** the template adds an "Anonymize mode active" block:
  - Conventional commit message **short and essential** (subject + minimal body, no narration,
    no tool trailers — already natively off via `settings.json`, reiterated).
  - **No trace comments** in the code (`// added by Claude`, task/AI references, generated
    TODOs): write only comments a human author would write.
  - **No slop files** (redundant READMEs, scratch): only the files required by the plan.
  - **No unrequested decorative emoji**; concise docs.
- **Architect dispatch (Step 2):** the template asks for **concise** ADR/plan, without meta-comments
  on the tool. (The architect writes only docs, not code; the constraint is of style/conciseness.)
- **Gate summaries:** unchanged in form, but the box shows `Anonymize: ON` for transparency.

**Coexistence with `coder.md` (verified: no anonymous rule today):** the coder already drafts a
Conventional Commit for the orchestrator and never commits (line 23/76). The anonymous mode
**does not contradict** the Pre-flight Pattern Classifier (ADR-0001) or any existing rule: it
adds only output constraints (conciseness, no-trace) conveyed in the prompt, not in SKILL.md.
When `anonymize=false` (default), the templates remain **identical to today** -> zero regressions
on current chain behavior. The anonymous mode is purely **additive and opt-in**.

### D8 — Safety / fail-mode: every destructive operation behind explicit HITL + backup; honest harness

- **HITL on every destructive operation** (rewrite, force-push, file deletion): never automatic,
  never from sub-agent (consistent global rule "HITL gate before permanent deletions / push" and
  ADR-0009). The skill **proposes**, the user **confirms**.
- **Backup before destructive** (global rule "back up before critical files"): tar of `.git/`
  before rewrite/fresh-history; branch/tag backup before rewrite (SPEC R5).
- **Dry-run before apply** (SPEC R5): rewrite shows expected diff before applying.
- **Auto mode classifier:** if the chain runs in auto mode and attempts a force-push, Claude
  Code's classifier will still ask for confirmation on a destructive operation — consistent with
  the choice (constraint §8 of dispatch). The skill does not bypass this behavior.
- **Harness (honest testability):** the `clean-public-repo/tests/run-tests.sh` harness (bash
  3.2-clean, target declared in the plan) verifies ONLY what is pure and deterministic:
  structural anchor on SKILL.md (contract sections + "orchestrator-only" + "no author
  falsification" + documented LIMITATIONS section), smoke of `detect-public-remote.sh`
  (non-git -> silent; non-github remote -> silent; no remote -> silent) on `mktemp -d` fixtures,
  and smoke of grep detection on a fixture with known markers (finds expected patterns, does NOT
  find a `claude-foo` dependency marked as review-needed). **NOT verifiable headless:** real
  rewrite, real fresh-history publish, force-push, gitleaks/gh integration on a real remote ->
  remain **open questions, validatable only in a pilot** with a real repo (honesty as
  ADR-0008/0009/0010). Never mock the entire git session (would test the mock).

---

## Alternatives considered (for each of the 8 questions)

The architectural approach alternatives come from the BRAINSTORM (A/B/C/D); for sub-decisions
the rejected options are listed with the reason.

### Global approach (from the BRAINSTORM)

- **Alternative A — prevention only (clean-by-construction):** rejected as complete architecture.
  Covers new repos at zero cost, but **does not cover existing ones** (e.g. already published
  Obsidian plugin) which are explicitly in scope (SPEC R6). Adopted as *part* of the hybrid
  (anonymous mode in the chain).
- **Alternative B — remedy only (scan + scrub on-demand):** rejected as complete architecture.
  Covers existing, but new repos would accumulate traces to clean every iteration (avoidable
  repeated work). Adopted as *part* of the hybrid (standalone skill).
- **Alternative C — prevention+remedy hybrid **: **adopted**. Each case uses the right approach
  (new->A, existing->B); covers the entire SPEC scope. Accepted against: two surfaces to maintain
  (mitigated by reuse — the chain does not duplicate the skill).
- **Alternative D — fresh-history publish **: **adopted** as the **default strategy for
  already-public** (D5). Avoids force-push on the original repo entirely (TOP risk of the
  pre-mortem). Accepted against: historical granularity is lost in public (compensated by
  surgical rewrite as option 2 for those who want it).

### D1 — Where to insert the gate

- **Extend Gate 0 (chain-vs-lightweight triage):** rejected. Mixes two orthogonal decisions
  (chain-vs-lightweight vs anonymous-yes/no) in a single prompt; makes it impossible to present
  one without the other and confuses the UX. Dedicated Gate 0b is clearer and separately
  deactivatable.
- **Auto-apply anonymous mode on every public GitHub remote (no `[y/n]`):** rejected. Violates
  SPEC R1 ("user decision, not auto-applied") and the ethical framing (the mode is a conscious
  user choice, not an imposed default).
- **Visibility detection from the remote URL alone (no `gh`):** rejected. A
  `github.com/...` URL does not reveal visibility (can be private); inferring "public" from the
  URL would cause false positives that disturb on private repos (violates R1 "silent on private").
  The cascade uses `gh` and treats indeterminate as non-public (fail-safe).

### D2 — Skill form / dependencies

- **Custom rewriter in bash (no git-filter-repo):** rejected. Rewriting a history by hand is
  error-prone and risky (TOP risk); `git-filter-repo` is the mature standard with dry-run and
  protections (researcher report). Do not reinvent a critical data-safety tool.
- **HARD dependency on gitleaks for detection:** rejected — **gitleaks is absent on the
  environment** (verified). Would make the skill unusable out-of-the-box. Primary detection
  must be custom grep (zero-dep); gitleaks is an optional bonus.
- **Dedicated sub-agent for cleanup:** rejected. Destructive git operations require interactive
  HITL; a sub-agent in auto mode must not execute them (consistent ADR-0010 D1 / ADR-0009).
  The skill runs on the orchestrator.

### D3 — Detection

- **Semantic/ML detection (recognize "AI style"):** rejected. Out of scope, non-deterministic,
  not bash 3.2-clean; the irreducible need (BRAINSTORM first-principles) is to remove **known
  lexical markers**, not guess style.
- **Only gitleaks (no custom grep):** rejected. gitleaks is secret-oriented and absent on the
  environment; tool markers (trailers, comments, emoji) are not its primary target and would
  require custom rules anyway. Custom grep is the right engine and zero-dep.
- **Automatic removal of all matches (no confirmation):** rejected. Violates SPEC R2 ("no blind
  removal") and the false-positive case (dependency `claude-*`). The action is hybrid: signal ->
  remove on confirmation.

### D4 — Report contract

- **Report without LIMITATIONS section:** rejected. It is the explicit requirement from the
  BRAINSTORM (false sense of security): a report that does not declare what it does NOT cover
  (binaries, metadata, generated) induces the user to believe the repo is "100% clean". The
  COVERAGE & LIMITATIONS section is mandatory.
- **Output only in chat (no file):** rejected. A cleanup audit must be persisted for human review
  and for re-execution; the file is the record of the confirmed action.
- **Delete slop files by default:** rejected. SPEC R2 + false-positive edge: slop files are
  signaled as `manual`, the decision remains human.

### D5 — Fresh-history publish

- **Force-push on the original repo (in-place rewrite as default for already-public):** rejected
  as default. It is the TOP risk of the pre-mortem (corrupts/loses the repo, breaks clones/forks,
  is visible and suspicious). Default = derived repo; in-place rewrite only as explicit option 2
  (D6).
- **Rewrite the original repo history and make it private:** rejected. More complex and risky
  than simple orphan branch + derived repo; no reason to touch the original.
- **Manual interactive squash (no orphan):** rejected as mechanism. Orphan branch is idiomatic
  and deterministic (researcher report); interactive rebase is manual, error-prone, and not
  safely automatable.

### D6 — Surgical rewrite

- **`git filter-branch`:** rejected. **DEPRECATED** (researcher report), slow, error-prone;
  git's own documentation recommends `git-filter-repo`.
- **BFG Repo-Cleaner:** rejected. Excellent for large blobs/known secrets, but **not suitable
  for arbitrary text replacement** of markers (researcher report); `git filter-repo
  --replace-text` covers the case.
- **Automatic rewrite without dry-run / without fresh-clone:** rejected. Violates SPEC R5 and
  the TOP risk; git-filter-repo's fresh-clone protection must be respected, not bypassed with
  `--force`.

### D7 — Anonymous mode in the chain

- **Patch `coder.md`/`architect.md` with the anonymous rule:** rejected. Would make the rule
  global and always-active (even outside the chain, even on private repos), and would create an
  "old contract to deprecate". The system pattern is to convey conditional directives in the
  **dispatch prompt-template** (like the additive directive of claude-md-generator): additive,
  opt-in, zero regressions when off.
- **Separate layer (post-processing commits after the coder):** rejected. A post-processor that
  rewrites just-made commits is effectively a mini-rewrite (risk) for something obtainable for
  free by having the coder write correctly from the start (prevention = Alternative A). Better
  clean-by-construction.
- **Stylistic normalization to deceive human review:** rejected — **out of scope for ethical
  constraint** (SPEC §"Ethical framing", out-of-scope). The mode removes markers and cares for
  quality; it does not mask the nature of the work from those who ask.

### D8 — Safety / fail-mode

- **Automatic force-push in auto mode:** rejected. Irreversible remote destructive operation;
  always behind HITL (consistent ADR-0009, global rule). Auto mode does not exempt from the
  human gate on destructive operations.
- **No backup before rewrite:** rejected. Violates SPEC R5 and the global rule "back up before
  critical files"; without backup the TOP risk is not mitigable.
- **End-to-end harness with a real git repo + remote:** rejected. Would require a real GitHub
  remote, real force-pushes, and would still not be deterministic/headless. The harness covers
  the pure parts (detection, remote-detection fail-safe); the rest is an open question from the
  pilot (honesty ADR-0008/0009/0010). Never mock the entire git session.

---

## Consequences

### Positive

- **Covers the entire SPEC scope:** new repos (prevention via anonymous mode) + existing
  (remedy via skill), with the right history strategy for each case.
- **TOP risk mitigated by design:** the default for already-public (fresh-history publish) avoids
  force-push on the original repo entirely; surgical in-place rewrite is opt-in with
  backup+dry-run+HITL. No unprotected destructive rewrite (priority #1).
- **Zero-dep out-of-the-box:** the skill works with only `git` (present); gitleaks/gh improve
  coverage but are not required (verified: gitleaks absent).
- **Clean reuse:** the chain does not duplicate the cleanup logic; the anonymous mode is additive
  via prompt-template (zero regressions when off). 4th instance of the standalone skill + chain
  gate pattern.
- **Ethical transparency:** the report declares COVERAGE & LIMITATIONS (no false sense of
  security); the feature does not falsify authors (commit remains attributed to Stefano).
- **Detection with context:** false positives (`claude-*` dependencies, "AI" in names) marked
  `review-needed`, never blindly removed (SPEC R2).

### Negative

- **Two surfaces to maintain** (anonymous mode in the chain + standalone skill) — accepted cost
  of the hybrid, mitigated by not-duplicating (the chain redirects to the skill).
- **Limited lexical detection:** custom grep does not catch semantic/stylistic traces or markers
  in binaries/generated files. Limitation declared in the report (LIMITATIONS); does NOT guarantee
  total indistinguishability.
- **Undeterminable remote visibility without `gh`:** on an environment without authenticated `gh`
  Gate 0b never activates (fail-safe towards silent) -> automatic prevention does not start; the
  user can still activate it manually or use the skill. Accepted conservative trade-off.
- **Real history operations not testable headless:** rewrite/fresh-history/force-push validatable
  only in pilot; harness covers only pure parts. Known limitation (ADR-0008/0009/0010).
- **Dependency on `git-filter-repo` for option 2:** if removed from the environment, the surgical
  rewrite is disabled (graceful degrade with install message); fresh-history remains available.

### Neutral

- **Manifest schema 1.2:** new optional field `anonymize: false` (default); 1.0/1.1 remain valid
  (additive retrocompat). `manifest-validate.sh` must be extended to accept 1.2.
  **Coexistence note:** ADR-0010 (web-e2e-test) already planned a 1.1->1.2 bump (`artifacts.e2e`
  + state `gate_6_e2e_web`). If ADR-0010 is deployed first, this ADR reuses the existing schema
  1.2 and adds ONLY the `anonymize` field (additive, no new state — Gate 0b is a check, not a
  state); if ADR-0010 is not yet deployed, this ADR introduces 1.2 with `anonymize`. In both
  cases 1.2 remains retrocompat 1.0/1.1; the plan verifies the live schema state before editing
  the regex (see plan, Coexistence notes).
- **New convention `docs/clean-report/`** for reports; optional, created on-demand.
- **Gate 0b is not a state** of the state machine (like Gate 0): it is a conditional check in
  `step_0_init`. No new state -> no extension of `VALID_STEPS`/transition pairs for the gate
  (only the `anonymize` field).
- Repo `vibe-coding-system` NON-git: the deliverables are the markdowns; the deploy of the live
  artifacts (`~/.claude/skills/clean-public-repo/`, chain patch) is a separate task (TDD plan),
  without commit step.

---

## References

- SPEC: `/Users/stefanoferri/Developer/vibe-coding-system/SPEC.md` (R1-R6, edge cases, DoD,
  ethical framing)
- BRAINSTORM: `/Users/stefanoferri/Developer/vibe-coding-system/BRAINSTORM.md` (Alternatives
  A/B/C*/D*, pre-mortem TOP risk, COVERAGE & LIMITATIONS requirement)
- ADR-0003 — `docs/architecture/ADR-0003-concept-to-code-chain.md` (chain + manifest YAML + HITL gates)
- ADR-0008 — `docs/architecture/ADR-0008-concept-to-code-workflow-v2-brainstorm.md` (optional
  gate + non-terminal skill invoked by chain; schema 1.0->1.1; honest harness)
- ADR-0010 — `docs/architecture/ADR-0010-web-e2e-test.md` (pattern standalone skill + gate;
  schema 1.1->1.2; fail-safe detection towards safe default; honest non-headless testability)
- ADR-0009 — `docs/architecture/ADR-0009-db-backup-guardrail.md` (HITL on destructive operation;
  backup as precondition; asymmetric fail-mode)
- ADR-0001 — `docs/architecture/ADR-0001-coder-preflight-pattern-classifier.md` (the anonymous
  mode coexists with the Pre-flight Pattern Classifier, does not contradict it)
- `~/.claude/skills/concept-to-code/SKILL.md` (state machine; gate->skill reuse pattern;
  additive directive via prompt-template — §3 Step 3)
- `~/.claude/skills/concept-to-code/scripts/manifest-validate.sh` (schema regex line 29,
  VALID_STEPS lines 57-72)
- `~/.claude/agents/coder.md` (no anonymous rule today; drafts commit for orchestrator, does not
  commit — coexistence D7)
- Prior-art tooling (researcher report): `git-filter-repo` (surgical rewrite standard,
  `--replace-text`/`--message-callback`/`--dry-run`, rejects non-fresh-clone; install
  `brew install git-filter-repo` / `pip3 install git-filter-repo`); `git filter-branch`
  DEPRECATED; BFG not suitable for arbitrary text; `git checkout --orphan` for fresh-history;
  `gitleaks` for detection (custom rules `.gitleaks.toml`, JSON output) — optional here;
  backup `tar -czf` of `.git/` + `--dry-run` as safety best practice.
- `feedback_bash32-constraint` (harness + bash 3.2-clean scripts)
- Verified environment facts 2026-05-23: `git-filter-repo` present (`/opt/homebrew/bin`),
  `gitleaks` absent, harness baselines (review-triage-fix 60, concept-to-code 20, etc.)
