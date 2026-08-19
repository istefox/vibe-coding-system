# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is this repository

This is not a code project: it is the **blueprint repository** for the "Vibe Coding System for
Stefano Ferri — Multi-Agent Architecture v2.1". It contains one authoritative artifact:

- `docs/vibe-coding-system.md` (~1770 lines) — complete specification of the multi-agent Claude Code
  setup: sub-agents, agent-teams, path-scoped rules, hooks, MCP, permission modes,
  concept→code workflow. This is the **single source of truth**: every decision must be reconciled
  with this document.

The file exceeds 25k tokens: read it with `Read` using `offset`/`limit` per section, not
in one block. Sections are numbered (1–17) and cross-reference each other throughout the text.

## Inherits global rules

This project inherits `~/.claude/CLAUDE.md` (Stefano Ferri), loaded in every session.
**Do not duplicate here** the general conventions (Python/Swift/web style, git workflow,
Vibrofer terminology, safety): they already apply. This file specializes only for this repo.

## Invariant behavioral rules

From section 4 of the document, consistent with global conventions — apply here and to
any system generated from this blueprint:

- Plan mode required for any task modifying >1 file or touching production migrations/config
- Conventional Commits in English (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`, `perf:`)
- Never `git push --force` without explicit approval from Stefano
- Never modify migrations already applied in production
- Never disable a test to make it pass: if it needs changing, explain why in chat first
- Confidence declared in chat at end of task, **never** in deliverable files
- HITL gate always before: commit, push, deploy, DB schema changes, permanent deletions
- Language: English throughout — chat, docs, code, commits, docstrings
- Tone: direct, concise, technical — no filler

## Architecture described in the document (big picture)

Use this to orient without re-reading all 1770 lines. Details and rationale in the indicated sections.

- **Topology (sec. 2):** Orchestrator (main CLI session) → up to 4 sub-agents in parallel *within*
  the session (isolated tasks, return summary) **or** 3–5 teammates in an agent-team in *separate
  sessions* (cross-layer work, experimental, `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`). Sub-agents
  do NOT spawn other sub-agents.
- **8 custom sub-agents (sec. 3)** in `~/.claude/agents/`: `architect` (Opus, plans, ADR only),
  `coder` (Sonnet, `isolation: worktree`), `reviewer`/`tester`/`debugger`/`refactorer` (Sonnet),
  `doc-writer`/`researcher` (Haiku). Model chosen to balance cost/capability (sec. 3.9).
- **Layered extension stack:** `~/.claude/CLAUDE.md` global (identity+behavior only, <200 lines)
  → path-scoped rules in `.claude/rules/` with `paths:` frontmatter (sec. 5) → sub-agents in
  `.claude/agents/` → skills in `.claude/skills/` (sec. 8) → hooks in `settings.json` (sec. 7,
  deterministic automation) → MCP in `.mcp.json` (sec. 9). The rules pattern replaces most of
  the monolithic CLAUDE.md.
- **Permission strategy (sec. 10):** `acceptEdits` default, explicit plan mode for new features,
  allowlist for recurring commands; hook-deny rules override any permission mode (layered defense).
- **concept→code workflow (sec. 11):** interview mode (`AskUserQuestion`) → `SPEC.md` → `ARCH.md`
  (+ ADR) → project CLAUDE.md → **fresh session** → scaffold in plan mode → parallel multi-agent
  implementation (worktree) → review → commit + PR. Never mix interview and coding in the same session.
- **Identity convention (sec. 4, proposed design element):** assistant "Adriano", user "Stefano" —
  noted here as a blueprint element; effective identity is governed by `~/.claude/CLAUDE.md`.

## Working with the document

- When updating `docs/vibe-coding-system.md`: keep section numbering consistent, the
  "Changes from…" blocks (version changelog at the top), and the "Final confidence" +
  "Verified vs assumed" section at the bottom.
- Preserve the explicit **verified vs assumed** distinction: the document cites
  `code.claude.com/docs` as verified primary sources. Do not promote an assumption to
  a fact without verification and a citation.
- The checklists (sec. 15) and templates (sec. 4, 6) are intended to be copied into other
  repos: keep them self-consistent and valid as standalone documents.

## Commands

Documentation-only repository: **no** build, lint, test, or run commands.
Markdown only. Remote: `https://github.com/istefox/vibe-coding-system` (private).
The artifacts of the described system (agents, skills, hooks, rules) live in `~/.claude/`
and in the `.claude/` directories of target projects — not here.


## Rules

Nineteen invariants this repository learned by getting them wrong, each with the one-clause reason
that makes it more than a slogan and the ADR that established it. **They are stated here once.**
Until issue #380 they were restated across 95 narrative blocks — over two hundred times — which is
what made this file ~75,000 tokens in every orchestrator turn.

The narrative behind each rule, including the measured counterexample, is in
`docs/chain-decisions.md`. Read it when a rule's reason is not enough; do not restate it here.

**This list is hand-curated, and that is a limitation, not a shortcut.** "A rule" is not
mechanically enumerable — re-deriving the recurring-rule table produced different counts in both
directions depending on the needle — so nothing verifies that every rule worth promoting was
promoted. What *is* verified is that no line was lost: see ADR-0136.

1. **A needle must belong to the mechanism it asserts about, and to nothing else** ("rule 12").
   A scan whose needle is the NAME of the thing it checks matches the prose explaining it, so the
   assertion passes a file with the mechanism deleted. The only way to know is to plant it.
   → ADR-0108.
2. **An assertion nobody planted pins nothing.** Every assertion must be seen RED against a
   declared plant (`# plant:` at column 1, `plant-check.sh`). A plant that does not fire is
   evidence about the assertion, not a formality — and inspect what the plant actually produced
   before believing what it reports. → ADR-0108, ADR-0090.
3. **A prose assertion must not depend on decoration.** A clause is the same clause whether it
   wraps across lines, is backticked, is bolded, or opens a sentence. Match a flattened,
   undecorated, case-insensitive copy. Structural markers stay line-wise, because there the
   decoration *is* the structure. → ADR-0073, ADR-0076, ADR-0080, ADR-0098, ADR-0101.
4. **"Did not run" is not "found nothing".** A check that could not execute must report a state
   distinct from a clean result — conventionally exit 3. Collapsing them means an unrun check reads
   as a pass, which is how a guard stays green for months. → ADR-0046, ADR-0076.
5. **A checker and a reporter have opposite caller idioms, and the call site must say which it is.**
   A checker is branched on by exit code; a reporter always exits 0 and signals on stdout, printing
   `CLEAN` when it finds nothing. Never `[ -n "$out" ]` (true even on `CLEAN`), never
   `grep -c … || echo 0` (a two-line `0\n0` on no match — use `|| true`). → ADR-0047, ADR-0048.
6. **Extract only when two copies giving different answers would be a defect.** Copies answering
   *one* question must be extracted; copies answering *different* questions stay copies, because a
   shared source that fails disables every consumer at once. → ADR-0069, ADR-0086.
7. **Guard the denominator, not only the matches.** Zero matches can be correct; zero *candidates*
   is a broken derivation, and from outside they look identical. Every derived population carries a
   count guard. → ADR-0085.
8. **Ask which direction the check runs in.** A check that validates the entries of a list is blind
   by construction to what the list omits. Run it backwards as well. → ADR-0043.
9. **A waiver that covers nothing reads as clean.** Every exemption mechanism needs a reverse check
   asserting the exemption still has a subject, or a stale waiver survives its reason. → ADR-0081,
   ADR-0084.
10. **A floor absorbs its own plant.** An assertion of the form `>= N` against a population with
    slack still passes when its plant removes one member. Prefer a frozen per-item baseline or an
    exact count; keep a floor only as a vacuity guard, and say so at the site. → ADR-0124.
11. **A manifest field has three states, not two: ABSENT, INVALID, UNREADABLE.** Read it through
    `manifest-field-state.sh`, never a bare `m.get()`, and decide what absence means from the
    manifest's `current_step`. Two call sites may apply opposite policies to the same ABSENT state
    and both be right. → ADR-0076, ADR-0109.
12. **A cross-reference names a distinctive anchor, never a line number.** Line numbers rot, and
    they rot fastest in files being actively corrected. A `<file>:<digits>` string that is
    genuinely not a reference is declared on one line in the file carrying it:
    `xref-exempt: <token>|… — <reason ≥ 40 chars>`. → ADR-0082.
13. **Measure the premise before designing on it.** Across Phase 8, measuring changed the direction
    or the premise on seven of twelve issues. A count in an issue, an ADR or a brief is a snapshot
    of its moment: re-derive it from the files. → ADR-0121, ADR-0122.
14. **A historical record is not corrected in place.** A number inside a completed ADR or manifest
    is a correct snapshot of its day; rewriting it falsifies the record for no consumer. Record the
    correction forward, in a dated `## Correction`. → ADR-0034, ADR-0075, ADR-0078.
15. **A bash fence in a `SKILL.md` that can abort declares itself and is executed by a test.**
    `<!-- fence-contract: <id> -->`, or `<!-- fence-illustration: <reason> -->` on one line. It
    carries no positional-parameter token (skill arguments are substituted into the markdown before
    the model sees it) and it runs its body under `bash` via a quoted heredoc whose terminator sits
    at column 0 (the host shell is zsh and does not word-split). → ADR-0083, ADR-0132, ADR-0133.
16. **An instruction is not an enforcement.** Prose in a `SKILL.md` that a model is asked to follow
    is a changed failure *shape*, not a guarantee. Say which one a feature ships; a green harness
    pinning that an instruction exists is not evidence it is obeyed. → ADR-0047, ADR-0088.
17. **A producer specified in one place and consumed in another needs something checking they
    meet.** A state that nothing produces, a helper that nothing calls, a remedy naming a command
    that does not exist — all three shipped here, all three passed review. → ADR-0071, ADR-0095,
    ADR-0099.
18. **A scan is satisfied by the whole population it searches, not by the part it meant.** An
    identifier whose namespace restarts per feature, matched against a repo-wide file set, is
    satisfied by a stranger's file: measured, every one of 199 declared requirement ids passed on a
    foreign match. Rule 7 guards a denominator that collapsed to zero; this is the same failure with
    the denominator too large, and it reads as coverage just as convincingly. → ADR-0138.
19. **A deleted assertion leaves a comment where it stood, naming the issue and the ADR.** Nothing
    counts assertions between runs, and nothing usefully can: a frozen per-file baseline would need
    a deliberate bump on 95 of the last 100 harness-touching commits, which is a tax and not a
    guard. What has actually kept deletions honest is the note left behind — 3 of 3 measured drops
    carry one. Enforced for the 371 planted assertions, where `plant-check.sh` reports `NOFIRE`;
    an instruction for the other 2622 (rule 16). → ADR-0150.

## Chain decision index

One line per ADR that has a narrative block, in the order the blocks were written. The narrative —
the measurement, the alternatives rejected, the lesson — is in `docs/chain-decisions.md` under a
heading naming the same ADR. Open the ADR itself for the full decision record.

- **ADR-0011** — anonymization for public repos: Gate 0b auto-detect + the `clean-public-repo` skill → `docs/architecture/ADR-0011-clean-public-repo-anonymize.md`
- **ADR-0015** — the `humanize-en` skill and its chain wiring (superseded in scope by ADR-0040) → `docs/architecture/ADR-0015-humanize-en-chain-integration.md`
- **ADR-0016** — Dynamic Workflows as Step 5's parallel coder dispatch, with `agent_batch` as the fallback → `docs/architecture/ADR-0016-dynamic-workflows-step5.md`
- **ADR-0018** — the `deep-refactor` skill and its two mandatory report-only guards → `docs/architecture/ADR-0018-deep-refactor-skill.md`
- **ADR-0019** — the `claude-md-slim` skill and its content-preservation hard gate → `docs/architecture/ADR-0019-claude-md-slim-skill.md`
- **ADR-0020** — `autopilot-build`: unattended Steps 5-7, local and reversible actions only → `docs/architecture/ADR-0020-autopilot-build-skill.md`
- **ADR-0022** — overnight roadmap-to-PR: unattended push and PR allowed under a per-repo opt-in; merge stays human → `docs/architecture/ADR-0022-nightly-autopilot-goal.md`
- **ADR-0023** — Phase P: generate the missing design inputs from a labelled GitHub backlog → `docs/architecture/ADR-0023-nightly-auto-design.md`
- **ADR-0024** — vendoring the deployed-only executable surface into `staging/` → `docs/architecture/ADR-0024-28-vendor-deployed-only-skills-and-hooks.md`
- **ADR-0025** — refreshing every stale `staging/` copy as a byte-identical mirror → `docs/architecture/ADR-0025-29-refresh-stale-staging-copies.md`
- **ADR-0026** — the private-history leak in `clean-public-repo`: relocate the backup outside the repo, hard-fail if staged → `docs/architecture/ADR-0026-30-clean-public-repo-private-history.md`
- **ADR-0027** — BSD-safe slug stamp, Gate 2b as a read-only TOFU probe, one canonical gate order → `docs/architecture/ADR-0027-31-c2c-bsd-slug-autopilot-gates.md`
- **ADR-0028** — manifest-helper guards: invariant-9 count, exit-4 write contract, the PATH-RULE call sites → `docs/architecture/ADR-0028-32-manifest-helpers-guards.md`
- **ADR-0029** — session-scoping `hook-verify-workflow.sh` so a concurrent session cannot produce a false VERIFIED → `docs/architecture/ADR-0029-33-hook-verify-session-filter.md`
- **ADR-0030** — three scope guards: autopilot CWD, conductor manifest glob, nightly check 6 → `docs/architecture/ADR-0030-34-scope-guards.md`
- **ADR-0031** — refactor-snapshot newline bug, deep-refactor glob override and dirty-tree advice → `docs/architecture/ADR-0031-35-refactor-snapshot-deep-refactor.md`
- **ADR-0032** — whole-line semantics for the content-preservation gate: a prefix match is not preservation → `docs/architecture/ADR-0032-36-claude-md-slim-union-check.md`
- **ADR-0033** — `vibe-status` recursion guard, orphan-process fix, Active-chains wiring → `docs/architecture/ADR-0033-37-vibe-status-recursion-chains.md`
- **ADR-0034** — five hook fixes, and the precedent that historical ADRs are corrected forward, never in place → `docs/architecture/ADR-0034-38-hook-hardening.md`
- **ADR-0035** — six instruction-layer corrections across five standalone skills → `docs/architecture/ADR-0035-39-skill-text-corrections.md`
- **ADR-0036** — agent frontmatter reconciled with blueprint §3; `effort: max` is session-only and inert in a file → `docs/architecture/ADR-0036-40-agent-tool-scoping.md`
- **ADR-0041** — `agent-write-scope.sh`: the architect's write scope was prose, because frontmatter has no path restriction for `Write` → `docs/architecture/ADR-0041-58-agent-write-scope.md`
- **ADR-0045** — `agent-command-scope.sh`: a command-position denylist, a guardrail against a shortcut and explicitly not a sandbox → `docs/architecture/ADR-0045-58-interpreter-wrapper-bypass.md`
- **ADR-0042** — `Bash(git *)` narrowed to five read-only subcommands; the grant contradicted its own paragraph → `docs/architecture/ADR-0042-91-architect-git-grant.md`
- **ADR-0043** — the direction lesson: a check validating a list's entries is blind to what the list omits → `docs/architecture/ADR-0043-93-pairs-completeness.md`
- **ADR-0044** — `--global` DUPLICATE sections need a declared-and-verified exemption, not a widened union → `docs/architecture/ADR-0044-57-global-duplicate-union-check.md`
- **ADR-0038** — native builds serve Grep/Glob through Bash and ignore the frontmatter entries; intentional, not a regression → `docs/architecture/ADR-0038-63-native-build-agent-tool-resolution.md`
- **ADR-0039** — `post-write-check.sh`: advisory syntax-only per-write checks; no linters, because severity tracks configuration → `docs/architecture/ADR-0039-early-coder-feedback.md`
- **ADR-0040** — the humanize perimeter is the audience, not the format; automatic invocation removed → `docs/architecture/ADR-0040-humanize-en-scope-narrowing.md`
- **ADR-0046** — prefix-anchored secret detection and a dependency diff, both reporters, wired into `commit` Step 1 → `docs/architecture/ADR-0046-100-secret-scan-dependency-gate.md`
- **ADR-0047** — the weakening scan wired into every unattended commit path; the detector reports, the caller gates → `docs/architecture/ADR-0047-101-weakening-scan-wiring.md`
- **ADR-0048** — `R-NN` requirement coverage as a blocking Step 5 → Step 6 gate; `.md` is never a test file → `docs/architecture/ADR-0048-102-requirement-ids-coverage.md`
- **ADR-0067** — a chain-invoked skill must not carry `disable-model-invocation`; the guard is now class-level → `docs/architecture/ADR-0067-interview-driver-model-invocation.md`
- **ADR-0068** — one worktree isolation contract: `baseRef: "head"`, no `WorktreeCreate` hook, merge-back audits the base fork → `docs/architecture/ADR-0068-176-worktree-isolation-contract.md`
- **ADR-0069** — one canonical plan-task predicate, loaded not pasted, because three consumers gave three answers → `docs/architecture/ADR-0069-172-plan-task-form.md`
- **ADR-0070** — the diff-budget checker had never fired: four independent defects, three invisible until the first is fixed → `docs/architecture/ADR-0070-184-diff-budget-task-predicate.md`
- **ADR-0071** — Gate 4.0 is the producer the Step 5 pre-flight always assumed; `commit --no-pr` added for it → `docs/architecture/ADR-0071-173-step5-preflight-producer.md`
- **ADR-0072** — detect and HEAL a near-miss requirement id, bounded by what the repair can actually reach → `docs/architecture/ADR-0072-171-spec-id-near-miss-self-repair.md`
- **ADR-0073** — plan deviations get a disclosure, in-place assertion edits get a sentence: no diff rule separates them → `docs/architecture/ADR-0073-177-178-what-the-gates-do-not-see.md`
- **ADR-0074** — the self-arming marker class: a hook reading every `user` entry arms on its own documentation → `docs/architecture/ADR-0074-127-self-arming-marker-class.md`
- **ADR-0075** — `hook_verified` has four states; leniency is bounded by `current_step: completed` → `docs/architecture/ADR-0075-123-hook-verified-states.md`
- **ADR-0076** — THE RULE for additive manifest fields: ABSENT, INVALID and UNREADABLE are three states → `docs/architecture/ADR-0076-195-additive-field-state.md`
- **ADR-0077** — THE RULE for transcript scans: read only the FIRST `user` entry, or declare why not → `docs/architecture/ADR-0077-193-transcript-scan-class-guard.md`
- **ADR-0078** — invariant 4's `project_root` check is conditional on a terminal state, derived from the transition graph → `docs/architecture/ADR-0078-197-project-root-terminal.md`
- **ADR-0079** — the permission layer bounds the interpreter enumeration; what was unguarded is widening a grant → `docs/architecture/ADR-0079-196-grant-coverage-and-r2-boundary.md`
- **ADR-0080** — the pattern-enforce main-session fallback STAYS, on n=3, with a pre-registered drop condition → `docs/architecture/ADR-0080-194-fallback-verdict.md`
- **ADR-0081** — a validation loop that could not fail, and two `PAIRS` zone anomalies of which one was undeclared → `docs/architecture/ADR-0081-213-212-false-green-and-zone-anomalies.md`
- **ADR-0082** — THE RULE for cross-references: a distinctive anchor, never a line number; waivers on one line → `docs/architecture/ADR-0082-207-210-cross-reference-form.md`
- **ADR-0083** — THE RULE for abort-capable bash fences: declare a contract and be executed by a test → `docs/architecture/ADR-0083-206-fence-contract-coverage.md`
- **ADR-0084** — THE RULE for skill coverage: named by a test, or a declared exemption in the skill's own text → `docs/architecture/ADR-0084-211-skill-coverage-perimeter.md`
- **ADR-0085** — guard the denominator, not the matches; a derivation that stops resolving reads as coverage → `docs/architecture/ADR-0085-208-derived-guard-boundaries.md`
- **ADR-0086** — THE CRITERION for extraction: extract only when two copies giving different answers would be a defect → `docs/architecture/ADR-0086-derived-guard-pattern-not-extracted.md`
- **ADR-0088** — test authoring splits at sub-task granularity; 56 of 57 plans mix test and implementation paths → `docs/architecture/ADR-0088-241-test-authoring-split-granularity.md`
- **ADR-0087** — deployment and verification are two questions; the deployed-only registry declares the difference → `docs/architecture/ADR-0087-222-deployed-only-skills.md`
- **ADR-0089** — the manifest leaves the Step 5 dirty set, and only the manifest; the classifier is a declared fence → `docs/architecture/ADR-0089-239-step5-preflight-manifest-exemption.md`
- **ADR-0090** — an unattended pre-flight check that failed OPEN, four lines from the one fixed for the same reason → `docs/architecture/ADR-0090-258-check6-placeholder-fail-open.md`
- **ADR-0091** — one grammar for per-file budgets, and a `MALFORMED` token with a consumer that reads it → `docs/architecture/ADR-0091-246-per-file-budget-half-parse.md`
- **ADR-0092** — a documented value domain nothing writes: derive the written set and compare both directions → `docs/architecture/ADR-0092-240-step5-mode-value-domain.md`
- **ADR-0093** — macOS detection: two boundary sets, and the platform name counts only near a UI noun → `docs/architecture/ADR-0093-232-macos-detection-false-positives.md`
- **ADR-0094** — one permanent gitignore glob instead of a per-branch line; `git check-ignore`, not a literal grep → `docs/architecture/ADR-0094-250-triage-state-gitignore-glob.md`
- **ADR-0095** — Step 5.0.5 produces `step_5_implementation`, and the derived producer guard that found #265 → `docs/architecture/ADR-0095-248-transition-producer.md`
- **ADR-0096** — archive the outgoing SPEC on displacement: detect by CONTENT, write by NAME → `docs/architecture/ADR-0096-228-spec-archive.md`
- **ADR-0097** — Gate 4 spans two orthogonal axes; the missing cell forfeited five downstream gates → `docs/architecture/ADR-0097-237-gate4-implementation-axes.md`
- **ADR-0098** — two "recommended" markers that can disagree: the orchestrator wins and the divergence is shown → `docs/architecture/ADR-0098-227-gate0-recommendation.md`
- **ADR-0099** — the HITL gate trail: a helper with no call site, and a template with no `gate: 4` slot → `docs/architecture/ADR-0099-238-hitl-gate-audit-trail.md`
- **ADR-0100** — one count served two questions; `--count` guards, `--count-openers` does arithmetic → `docs/architecture/ADR-0100-242-batch-dispatch-openers.md`
- **ADR-0101** — batch-boundary precedence: evidence quality beats checkpoint tidiness → `docs/architecture/ADR-0101-247-batch-boundary-precedence.md`
- **ADR-0102** — Gate 2b skips when the exact command is already trusted; a gate that cries wolf is worse than a rare one → `docs/architecture/ADR-0102-233-gate2b-trust-probe.md`
- **ADR-0103** — a baseline sha survives a rebase as a state and not as an object: report three states, never halt → `docs/architecture/ADR-0103-244-recovery-baseline-rebase.md`
- **ADR-0104** — Step 7.0 collapses the Step 5 snapshots under four guarded refusals → `docs/architecture/ADR-0104-249-step7-snapshot-collapse.md`
- **ADR-0105** — `gate_5_review_decision` deleted: Gate 5 is the fifth inline sub-gate with no state of its own → `docs/architecture/ADR-0105-265-gate5-state-removal.md`
- **ADR-0106** — Step 7.0b archives on completion and repoints `artifacts.spec` away from the mutable slot → `docs/architecture/ADR-0106-267-spec-pointer-archive.md`
- **ADR-0107** — the fence-contract population was the abort-capable subset, so five declarations sat outside their own guard → `docs/architecture/ADR-0107-281-fence-contract-population.md`
- **ADR-0108** — the plant registry: a plant declared beside its assertion and executed against an isolated copy → `docs/architecture/ADR-0108-284-plant-registry.md`
- **ADR-0109** — `manifest-entry-state.sh`: seven entry tokens, because "no file" and "unparseable" are inputs, not environments → `docs/architecture/ADR-0109-319-manifest-entry-state.md`
- **ADR-0110** — the effective permission mode is in the transcript, not in `settings.json`; the gate fails closed → `docs/architecture/ADR-0110-320-permission-mode-preflight.md`
- **ADR-0111** — a contained per-feature skip versus a run-level halt, decided by the entry-state token → `docs/architecture/ADR-0111-324-conductor-entry-failure-split.md`
- **ADR-0112** — the stale guard marker and the destination rule that ran over the whole command → `docs/architecture/ADR-0112-321-323-stale-guard-marker.md`
- **ADR-0113** — terminality is two fields: `status: aborted` is terminal even when `current_step` is not → `docs/architecture/ADR-0113-331-invariant-4-two-field-terminal.md`
- **ADR-0114** — the required-checks audit: derive the live required set, and make a context satisfiable or abort → `docs/architecture/ADR-0114-322-required-checks-audit.md`
- **ADR-0115** — Gate 0's autopilot default is `standard`, because only standard completes with nobody present → `docs/architecture/ADR-0115-329-gate0-autopilot-default.md`
- **ADR-0116** — `acceptEdits` does not stop a Bash prompt; only `bypassPermissions` does, and six sites said otherwise → `docs/architecture/ADR-0116-339-permission-posture-overpromise.md`
- **ADR-0117** — the PATH-RULE class: the preceding word separates an instruction from prose, and form cannot → `docs/architecture/ADR-0117-286-path-rule-bare-mentions.md`
- **ADR-0118** — two gitignore entries where one was believed: the survivor is chosen for coverage, not symmetry → `docs/architecture/ADR-0118-287-rtf-gitignore-glob-resolution.md`
- **ADR-0120** — the transition-pair count is 45, derived by one shared checker instead of three disagreeing copies → `docs/architecture/ADR-0120-289-transition-pair-count.md`
- **ADR-0121** — widening a plan predicate was rejected on measured cost: 20 of 22 affected plans are collateral → `docs/architecture/ADR-0121-290-plan-shape-predicate.md`
- **ADR-0122** — a bold-wrapped requirement id reads as DECLARED; one `strip_emphasis()` shared by reader and repairer → `docs/architecture/ADR-0122-291-bold-wrapped-requirement-id.md`
- **ADR-0124** — a frozen per-manifest baseline replaces a hand-maintained floor, because a floor absorbs its own plant → `docs/architecture/ADR-0124-346-spec-pointer-baseline.md`
- **ADR-0125** — the value-domain guard extended to two more fields; a type is not a value set → `docs/architecture/ADR-0125-292-value-domain-guard-two-fields.md`
- **ADR-0129** — `autopilot` gains `--features`/`--only`/`--dry-run`; `token-budget` removed because a PreToolUse hook cannot stop the feature that breached it → `docs/architecture/ADR-0129-365-scope-and-bound-the-autopilot-run.md`
- **ADR-0131** — the mode marker names the QUESTION, never the mode, so a changed flag is caught → `docs/architecture/ADR-0131-294-plan-tasks-mode-binding.md`
- **ADR-0132** — skill arguments are substituted into `$<digit>` tokens in the markdown body, bash fences included → `docs/architecture/ADR-0132-385-skill-args-in-fences.md`
- **ADR-0133** — a bash fence is executed by the HOST shell; wrap the body in a quoted heredoc run under `bash` → `docs/architecture/ADR-0133-394-fence-execution-shell.md`
- **ADR-0134** — Phase P step 3 reads roadmap state and the `--only` list, not just whether a SPEC file exists → `docs/architecture/ADR-0134-399-phase-p-roadmap-state.md`
- **ADR-0135** — the terminal transition moves ahead of the `commit` invocation; the invariant is phrased over WRITES → `docs/architecture/ADR-0135-410-completed-transition-before-commit.md`
- **ADR-0137** — the stop-gate trigger is bounded by a project-owned path list, and a timeout is counted like a block → `docs/architecture/ADR-0137-404-stop-gate-trigger-granularity.md`
- **ADR-0138** — the requirement-coverage test axis is tightened by SCOPE, because the measured defect was a repo-wide scan, not a comment → `docs/architecture/ADR-0138-312-spec-coverage-scope-not-assertion-shape.md`
- **ADR-0143** — the plant registry had already paid for isolation and was spending it one core at a time; the verdicts are pinned by a byte-identical diff → `docs/architecture/ADR-0143-350-plant-registry-parallel.md`
- **ADR-0144** — a detector retired on 0 true positives in 383 commits, and a heading whose zero instances are held there by two templates → `docs/architecture/ADR-0144-313-314-triage-outcomes.md`
- **ADR-0145** — the fired predicate gains a right anchor; 33 of 387 plants were exposed to a sibling and 0 were mis-credited → `docs/architecture/ADR-0145-355-anchored-fired-predicate.md`
- **ADR-0146** — a call to a helper the file does not define, guarded by a derived scan; the floor R-02 asked for is refused because a floor absorbs its own plant → `docs/architecture/ADR-0146-310-undefined-helper-scope.md`
- **ADR-0147** — a producer names the target as a destination, never as a mention; eleven producers on one target, one of them real, and the class guard could not be planted → `docs/architecture/ADR-0147-300-producer-destination-anchor.md`
- **ADR-0148** — the in-place assertion edit stays undetected at 0 of 6 over 383 commits; the refusal is disclosed at the enforcement point that never said so → `docs/architecture/ADR-0148-311-in-place-assertion-edit-refusal.md`
- **ADR-0149** — the plant declaration grammar was stated and enforced nowhere, so one plant had been mutating something nobody wrote; enforced, then widened to express an insertion → `docs/architecture/ADR-0149-305-plant-declaration-grammar.md`
- **ADR-0150** — the per-file assertion baseline refused at 95% friction and zero silent instances; the in-place deletion note becomes rule 19 → `docs/architecture/ADR-0150-449-vanished-assertion-baseline-refusal.md`
- **ADR-0151** — the registry's ceiling was two cores, so it becomes four shards and a union job; a matrix leg can never be a required context, and a union written the obvious way is green while its shards are red → `docs/architecture/ADR-0151-447-shard-the-plant-registry.md`
- **ADR-0152** — the archive fence looks for the file before it validates the slug; the empty-root bootstrap was a halt documented as a no-op, and the assertion that covered it tested a pair the caller cannot produce → `docs/architecture/ADR-0152-455-archive-fence-empty-root.md`
- **ADR-0153** — `project-tasks` is vendored and its ledger becomes a bilateral index of every open GitHub issue; the promotion counter is a derivation so an abort cannot corrupt it, and the skill was already declared deployed-only, so vendoring means deleting that waiver → `docs/architecture/ADR-0153-project-tasks-vendored-bilateral-ledger.md`
- **ADR-0154** — a scoped test file must name the feature back, because a plan legitimately cites other harnesses as precedents and each brings its own ids; two designs were refused on measurement and the adopted one drops 94 of 263 scoped files with zero coverage lost → `docs/architecture/ADR-0154-spec-coverage-scope-back-reference.md`
- **ADR-0155** — the tester's batch must leave the target building, because tester-first assumed a failing assertion still compiles and in Swift it does not; the hook already permitted the fix, so only the instruction was missing → `docs/architecture/ADR-0155-compiled-language-tester-batch.md`
- **ADR-0156** — the stop gate's per-session budget is spent by DISTINCT failures, not by repeats, because three blocks on one failing assertion are one piece of information and 5 of 16 sessions had spent the whole budget that way and then stopped guarding → `docs/architecture/ADR-0156-stop-gate-distinct-failure-budget.md`
- **ADR-0157** — a foreign feature's requirement id is not this feature's coverage: ids restart at R-01 in every SPEC, so the repo-wide mention scan credited a stranger's R-13 and an untested id read UNSCOPED, while the same population fed a false COVERED through the empty-scope fallback; the ownership key set is measured against two rejected ones and 12 of 130 corpus rows move → `docs/architecture/ADR-0157-cross-feature-requirement-id-collision.md`
- **ADR-0158** — Step 6 and Gate 5.06 stop committing their own corrections, because a mid-feature commit under a subject `_foreign` cannot attribute both aborted the Step 7.0 collapse and, left unstaged instead, was silently dropped by `commit`'s own staged-only scope rule; the collapse fence now runs `git add -u` after its soft reset to sweep either into the one feature diff → `docs/architecture/ADR-0158-step6-no-commit-collapse-sees-whole-feature.md`
- **ADR-0159** — a worktree isolates cwd, not a build's output directory, so concurrent `xcodebuild` runs shared one build root until `-derivedDataPath` is generated and pre-flight-gated; separately, the batch completion fact was read AFTER the merge-back's own `git worktree remove`, measured on git 2.50.1 to succeed and delete the marker with it, so a healthy batch spuriously halted on NONE → `docs/architecture/ADR-0159-one-build-root-completion-fact-before-merge-back.md`
- **ADR-0160** — `#` opens a macro in Swift, not a comment, so `#expect`/`#require` read as false negatives (32 findings against 12 real assertions in one field file); a `.swift` extension is not "this diff touched a view", so Gate 5.05 now checks content via `ui-file-detect.sh`; and ADR-0054's CE forward guard gains a declared, content-verified per-issue exemption rather than a reverted fix or a widened union → `docs/architecture/ADR-0160-hash-not-comment-in-swift-extension-not-view.md`
- **ADR-0161** — the stop gate stops re-running a suite against a tree nothing has touched since the last run: a sha256 fingerprint of `git status --porcelain` + `git diff HEAD`, checked BEFORE the suite runs rather than de-duped after (ADR-0156's cost was paid every time even on a repeat), fail-toward-running on any unreadable git state, cleared on every green run alongside the budget it already clears → `docs/architecture/ADR-0161-stop-gate-fingerprint-cache.md`
