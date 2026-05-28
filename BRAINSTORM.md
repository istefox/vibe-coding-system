# BRAINSTORM — Contribution anonymization mode for public repos

**Date:** 2026-05-23
**Requirements source:** /Users/stefanoferri/Developer/vibe-coding-system/SPEC.md
**Techniques applied:** first-principles, assumption-busting, prior-art, genuinely different alternatives, inversion/pre-mortem

## Problem restated (first-principles)

The irreducible need is not "delete the word claude", but **a public repo indistinguishable from one written by hand by a professional**: holistic quality (essential commits, concise docs, zero unnecessary files) + absence of any tool marker. Cleanup is a subset of quality, not the end goal.

## Challenged assumptions

- **"Cleaning always requires rewriting commit history"** — **DROPPED**. Three cases must be distinguished: (1) new repos → clean commits from the start, zero rewrite; (2) existing not-yet-public → surgical rewrite pre-push; (3) existing already-public → rewrite requires force-push (breaks clones/forks, is visible/suspicious) → better fresh-history publish.
- **"Detection must be lexical (grep strings)"** — **TO VERIFY**. The pattern is identical to secret-scanning; mature tools exist (gitleaks, git-filter-repo, BFG) → comparison delegated to researcher.
- **"Anonymous = no claude"** — **DROPPED/expanded**. First-principles shifts the target to "indistinguishable quality", not just token removal.

## Approach alternatives

### Alternative A — Prevention (clean-by-construction)
- **Idea:** anonymous mode in the chain produces output already compliant (clean commits/docs from the start); the skill only does a verification audit.
- **Axis of difference:** responsibility boundary (prevent vs remedy).
- **Pros:** zero rewrite for new repos; cleanup "for free". **Cons:** does not cover existing repos (Obsidian). **Cost:** low.

### Alternative B — Remedy (scan + scrub on-demand)
- **Idea:** standalone skill that scans any repo and remediates (including history rewrite).
- **Axis of difference:** deployment (standalone vs integrated in the chain).
- **Pros:** covers existing; decoupled. **Cons:** new repos accumulate traces to clean each time. **Cost:** medium.

### Alternative C — Prevention+remedy hybrid ★ (chosen)
- **Idea:** new repos → anonymous mode in the chain (A); existing → standalone `clean-public-repo` skill (B).
- **Axis of difference:** targeted combination for the scope (new + retroactive from SPEC).
- **Pros:** covers everything; each case uses the right approach. **Cons:** two surfaces to maintain. **Cost:** medium.

### Alternative D — Fresh-history publish ★ (chosen for already-public repos)
- **Idea:** for a repo already public, don't rewrite history but publish a **derived** public repo with a few curated commits; the development history (with traces) stays private.
- **Axis of difference:** deployment model (clean public mirror vs same repo rewritten).
- **Pros:** no force-push, no suspicious gaps, no risk of corrupting the original repo. **Cons:** granular historical detail is lost in the public copy. **Cost:** low-medium.

## Risks surfaced (inversion / pre-mortem)

- **[TOP] Destructive rewrite corrupts/loses a repo** → mandatory mitigations: automatic backup branch/tag + dry-run + confirmation; and **prefer D (fresh-history) for already-public repos**, which avoids force-push on the original repo entirely. In-place surgical rewrite remains a second-choice option, never the default.
- False positives (dependencies `claude-*`, "AI" in names) → removal-only-on-confirmation protects.
- False sense of security (trace not detected in binaries/metadata/generated files) → the report must explicitly declare the coverage and its limits (what was NOT scanned).

## Adjacent ideas surfaced

- **Bonus secret-scanning:** the same scan can flag real secrets (gitleaks patterns) — useful but *out of scope now*, noted as future.
- **Reusable "public mirror":** fresh-history publish is essentially a mirror-publication workflow, potentially useful regardless of anonymization — future.

## Preliminary recommendation (NOT binding, to be validated by architect)

**Hybrid C** as architecture (prevention for new repos via anonymous mode in the chain + `clean-public-repo` skill for existing ones), with **D (fresh-history publish)** as the default strategy for already-public repos and surgical rewrite only as an explicit second choice. Reuse of mature tools (git-filter-repo/gitleaks) instead of a custom rewriter — **to confirm with researcher**. Safety priority: backup + dry-run + confirmation on every destructive operation.

## Notes for the architect

- **Tool comparison (PRIORITY):** dispatch researcher for `git-filter-repo` vs `BFG` vs custom bash — reliability, dependencies, suitability for fresh-history vs surgical rewrite. (The orchestrator launches this before dispatching the architect.)
- **Where to graft the gate** in the chain state machine (extended Gate 0 vs dedicated gate): to decide in the ADR.
- **Detection:** evaluate reusing the gitleaks pattern-set for strings + custom set for tool-specific markers.
- **New requirement surfaced (add to SPEC if confirmed):** the clean report must declare the **coverage and limits** of the scan (what is not covered: binaries, metadata, generated files) to avoid a false sense of security.
- Skill name: `clean-public-repo` provisional; evaluate whether to separate the "fresh-history publish" part into a distinct capability.
