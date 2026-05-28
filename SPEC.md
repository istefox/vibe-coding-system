# SPEC — Contribution anonymization mode for public repos

**Date:** 2026-05-23
**Topic:** y/n gate in the `concept-to-code` chain + skill `clean-public-repo`

## Objective

Allow a public repo to be judged on **code quality**, not penalized for the tool used. The system produces clean repos (essential commits, concise docs, no unnecessary files) and **with no explicit traces of the tool** (trailers, comments, strings, emoji-slop). The work remains the user's: they direct it, review it, test it and are responsible for it.

## Ethical framing (constraint, not option)

- Purpose: **not advertising the tool** + **code quality**.
- NOT: falsifying authors (never attributing to real people who did not contribute), nor actively lying if someone explicitly asks.
- Tool attribution is already disabled natively (`settings.json: attribution {commit:"", pr:""}`).

## Scope

**In scope:**
1. **Activation gate** in the `concept-to-code` chain (auto-detect + confirmation): if the repo has a **public** GitHub remote, the chain proposes anonymous mode with `[y/n]`; on private/local repos it stays **silent**.
2. **Anonymous mode during the chain** (if activated): short/essential commits, concise docs, no slop files, no trace-comments — output already compliant.
3. **Skill `clean-public-repo`** (provisional name): audit + cleanup of a repo, both new and **existing** (retroactive cleanup, e.g., already-published Obsidian plugin).

**Out of scope:**
- Stylistic normalization to deceive human reviews (not done).
- E2E tests / other workflows (separate).

## Functional requirements

- **R1 — Activation:** auto-detect public GitHub remote → `[y/n]` gate. Silent on private/local. (User decision, not auto-applied.)
- **R2 — Hybrid action:** the skill **reports** (report "ready / needs-cleaning") and **removes on user confirmation**. Never blind removal.
- **R3 — What to clean (everywhere the trace may appear):**
  - Commit trailers (`Co-Authored-By: Claude`, `Generated with Claude Code`)
  - Trace comments in code (`// added by Claude`, references to tasks/AI, generated TODOs)
  - Slop / unnecessary files (redundant READMEs, scratch files) + bloated docs (to shorten)
  - `claude`/`AI` strings + decorative emojis not requested
  - Any other textual residue traceable to the tool
- **R4 — Existing commit history:** treatment **case by case with confirmation**. Rewrite changes SHAs → only **before a public push**.
- **R5 — Rewrite safety:** before rewriting history, **automatic backup branch/tag** + **dry-run** (shows what would change) before applying.
- **R6 — Retroactive scope:** the skill also works standalone on existing repos, not only from the chain.

## Operational constraints

- Bash 3.2-clean for all scripts (macOS system bash environment).
- Coexistence with the existing system (chain v2, active hooks, green harnesses) — anchor-preserving.
- Repo `vibe-coding-system` stays non-git; the feature operates on **target repos** (git).
- Language: docs/communication in English; code/commits in English.

## Edge cases

- Repo without remote / private remote → silent gate, mode not proposed.
- Repo with long history and many traces → mandatory dry-run + backup; rewrite can be costly.
- False positive on a legitimate string (e.g., a dependency genuinely named "claude-*", or "AI" in a domain name) → removal-on-confirmation protects; flag, do not remove blindly.
- Repo already publicly pushed → history rewrite requires force-push (destructive remote action): explicit HITL, never automatic.
- Detached branch / non-git → skill degrades without errors.

## Success criteria / Definition of Done

- Running `clean-public-repo` on a repo gives a **report** listing every trace found (by R3 category) with location.
- On confirmation, traces are removed; the repo stays functional (tests green pre/post).
- The gate in the chain fires only on public remotes and respects the `y/n` choice.
- History rewrite only happens with backup + dry-run + confirmation; never automatic force-push.
- Zero explicit residual traces in the R3 scope after a confirmed cleanup.
- No author falsification. No system test/guardrail broken (harnesses green).

## To decide in the design phase (brainstorm/architect)

- Exactly where the gate fits in the chain state machine (extended Gate 0 / dedicated new gate).
- Whether anonymous mode is a manifest flag that influences dispatch templates, or a separate layer.
- History rewrite technique (filter-repo / rebase / filter-branch) and related trade-offs.
- Skill architecture: bash + git, detection pattern set, report format.
- Definitive skill name.
