# ADR-0015 — humanize-en: English Prose Humanizer + Chain Integration

**Status:** Accepted  
**Date:** 2026-05-28  
**Author:** istefox  

---

## Context

Claude Code output in English has consistent, detectable AI tells (vocabulary: delve/tapestry/leverage/foster/showcase/pivotal; openers: Additionally/Moreover/Furthermore; structural: em-dash overuse, copula bloat "serves as", same-length sentence rhythm). On public repos this signals AI authorship, directly undermining ADR-0011's anonymize goal.

Brief: `/Users/stefanoferri/Documents/HUMANIZER-HOOK-BRIEF.md` (Stefano, 2026-05-28).

The brief proposed a three-layer architecture. Two proposed components were rejected as incompatible with the existing stack:
- **Global `UserPromptSubmit` hook (200 tok/prompt):** fires on every prompt including Italian-only sessions; net cost positive given the chat language was Italian at the time.
- **`PostToolUse` with `claude -p` subprocess:** adds LLM latency on every `.md` write; risk of recursive invocation; inconsistent with fail-open hook design.

---

## Decision

**Triple-trigger architecture** with a standalone skill and two zero-LLM hooks:

### Layer 0 — Chat language switch (global)

Changed default chat language from Italian to English in `~/.claude/CLAUDE.md`. Vibrofer domain terminology stays Italian regardless. Skill prompt templates (interview-driver, concept-to-code gates, review-triage-fix) stay in Italian — they are internal workflow instructions, not user-facing conversation.

Rationale: English chat saves ~20-30% tokens vs Italian (shorter tokens, same semantic density) and enables Layer 2b keyword detection to work on prompt text reliably.

### Layer 1 — Skill `humanize-en` (manual + chain-triggered)

Location: `~/.claude/skills/humanize-en/`

- `SKILL.md`: workflow (load rules → scan → rewrite → output with write gate)
- `rules.md`: authoritative rules reference (vocabulary, openers, structural, voice, commit-specific)
- `scripts/detect-ai-tells.sh`: bash 3.2-clean regex scanner (used by hooks and skill)
- `tests/run-tests.sh`: 13-point harness

Guardrails: no fact invention, no data alteration, style only.

Invocation modes:
- Manual: `/skill humanize-en [text|file-path]`
- Via Gate 5.5 in concept-to-code (post-review, pre-commit, conditional on `humanize=true`)
- Via Step 3.5 in commit skill (pre-gate, conditional on public remote)

### Layer 2a — `PostToolUse` hint hook

File: `~/.claude/hooks/post-md-tells-hint.sh`

Fires after `Write|Edit` on `.md` files. Runs `detect-ai-tells.sh`, prints a hint if ≥ 3 tells found. Exit 0 always. ~10ms, zero LLM.

### Layer 2b — `UserPromptSubmit` conditional hook

File: `~/.claude/hooks/prompt-en-prose-detect.sh`

Fires on every user prompt. Keyword regex matches EN prose-writing contexts (README, PR description, issue body, Reddit, HN, forum post, blog post, changelog, release notes, substack, dev.to, newsletter, announcement, Product Hunt). No match → exit 0 silent, zero overhead. Match → emits `additionalContext` JSON with ~80-token reminder. Expected hit rate < 10% of prompts.

### Layer 3 — Chain + commit integration

**concept-to-code:**
- Gate 0c (new): after Gate 0b (anonymize), if `detect-public-remote.sh` returns `public`:
  - if `anonymize=true` → auto-set `humanize=true` (consistent: anonymize implies humanize)
  - if `anonymize=false` → ask user via AskUserQuestion
- Gate 5.5 (new): post-review/pre-commit, conditional on `humanize=true`. Invokes humanize-en on each `.md` deliverable (README, changelog, doc inline). Followed by HITL confirmation before Step 7.
- Manifest flag: `humanize: true|false` (schema 1.2 additive, retrocompat)

**commit skill:**
- Step 3.5 (new): after Step 3 (generate message), before Step 4 (HITL gate). If `detect-public-remote.sh` returns `public`, pass subject+body to humanize-en inline mode. Humanized output feeds Step 4 gate — user approves the final version.

### Skill EN aliases

Added EN trigger aliases (additive, no body changes) to four skills:
- `concept-to-code`: "run the chain", "concept to code end-to-end", "new feature end-to-end"
- `commit`: existing EN triggers verified; added none (already covered in description)
- `interview-driver`: "interview me", "let's spec it", "new project from scratch"
- `review-triage-fix`: "review and fix", "full review cycle", "triage findings and fix"

---

## Consequences

**Positive:**
- AI tells removed from public-facing EN prose before commit or publication.
- Zero overhead on code-task prompts and Italian-only sessions.
- Pattern reuses detect-public-remote.sh and manifest flag pattern from ADR-0011 — no new primitives.
- Chain harness (PASS=29) extended with Gate 5.5 tests.

**Negative / risks:**
- `UserPromptSubmit` hook 2b may degrade Anthropic prompt cache (5-min TTL) if `additionalContext` invalidates cached prefixes. Measurement required post-deploy (see Validation).
- Gate 5.5 adds ~30-60s to chain on public repos (one humanize pass per deliverable file). Acceptable for documentation; skip is always available.

**Explicitly excluded (future work):**
- Full EN translation of skill prompt templates. Estimated 1-2 weeks, branch isolated, full regression harness required. Roadmap only — not blocking.

---

## Validation

1. `bash ~/.claude/skills/humanize-en/tests/run-tests.sh` → PASS=13 FAIL=0
2. Hook 2b: measure prompt cache hit rate via `/usage` for 48h post-deploy. If cache miss rate increases > 5%, degrade hook 2b to reminder-only (remove `additionalContext`, print to stderr only).
3. concept-to-code chain harness: PASS ≥ 29 (or updated baseline with Gate 5.5 tests).
4. Commit skill dry-run on public repo: verify humanize fires PRE-gate, user approves humanized text.
5. Commit skill dry-run on private repo: verify humanize is silently skipped.
6. `vibe-status` → 9/9 green post-deploy.

---

## Files changed

```
~/.claude/skills/humanize-en/              ← NEW (Layer 1)
~/.claude/skills/humanize-en/SKILL.md
~/.claude/skills/humanize-en/rules.md
~/.claude/skills/humanize-en/scripts/detect-ai-tells.sh
~/.claude/skills/humanize-en/tests/run-tests.sh
~/.claude/hooks/post-md-tells-hint.sh     ← NEW (Layer 2a)
~/.claude/hooks/prompt-en-prose-detect.sh ← NEW (Layer 2b)
~/.claude/skills/concept-to-code/scripts/manifest-set-humanize.sh ← NEW
~/.claude/settings.json                   ← EDIT (merge PostToolUse + UserPromptSubmit hooks)
~/.claude/CLAUDE.md                       ← EDIT (Layer 0: chat EN default)
~/.claude/skills/concept-to-code/SKILL.md ← EDIT (Gate 0c + Gate 5.5 + EN aliases)
~/.claude/skills/concept-to-code/scripts/manifest-validate.sh ← EDIT (humanize invariant)
~/.claude/skills/commit/SKILL.md          ← EDIT (Step 3.5 + EN aliases check)
~/.claude/skills/interview-driver/SKILL.md ← EDIT (EN aliases)
~/.claude/skills/review-triage-fix/SKILL.md ← EDIT (EN aliases)
~/Developer/vibe-coding-system/CLAUDE.md  ← EDIT (ADR-0015 note)
```
