---
name: humanize-en
description: Rewrites English prose to remove AI tells — no em-dash, no delve/tapestry/leverage/foster/showcase/pivotal/seamless, no paragraph openers Additionally/Moreover/Furthermore, active voice, varied sentence length, specific details over vague claims. Use ONLY for text an outside audience reads: Reddit/HN posts, forum threads, blog posts, newsletters, announcements, marketing copy, email to third parties. Triggers include "humanize this", "de-AI this", "sounds like AI", "remove AI tells", "make this sound human", "humanize-en", "/skill humanize-en". NEGATIVE: do NOT use for programming or internal artifacts — source code, config, commit messages, PR and issue text, ADRs, specs, plans, README and other repo docs, changelogs, release notes, or anything gitignored. Those are written plainly, with no humanize pass.
---

# `humanize-en` — English Prose Humanizer

Rewrites English text to remove AI tells. Style only — no facts are invented, removed, or altered.

## Guardrails (hard constraints)

- **Never invent facts.** If rewriting would require adding content, leave the sentence as-is.
- **Never change:** data, numbers, names, file paths, version strings, function names, code blocks.
- **Never remove content** unless it is a redundant AI opener or chatbot artifact with zero informational value.
- Style only: vocabulary, rhythm, voice, sentence structure.

## Invocation

```
/skill humanize-en [target]
```

- `target` (optional): file path OR inline text.
- If omitted: ask user to paste text or provide a file path.
- Manual invocation only. No skill and no chain step invokes this one automatically.

---

## Process

### Step 1 — Load rules

Load `~/.claude/skills/humanize-en/rules.md`. This is the authoritative rules reference.

### Step 2 — Load text

- If `target` is a path that resolves to an existing file → read the file.
- If `target` is inline text → use as-is.
- If no target → ask: "Paste the text to humanize, or provide a file path."

### Step 3 — Scan and report

Run a mental audit against the rules:
- Count vocabulary blacklist hits.
- Count opener violations.
- Note structural pattern issues (dashes/em-dashes, rule of three, inline bold headers).
- Note voice violations (passive, copula bloat, chatbot closers).

Report in one line: "Found N patterns: [comma-separated types]."
If 0 patterns: "No AI tells found — text looks clean."

### Step 4 — Rewrite

Apply all rules in a single pass. Priority order:
1. Replace vocabulary blacklist words with plain alternatives.
2. Rewrite paragraph openers that violate the opener list.
3. Fix copula bloat: "serves as" → "is", "stands as" → "is/has", "functions as" → "works as" or "is".
4. Break same-length sentence runs: insert a short sentence or split a long one.
5. Switch passive → active voice where the actor is clear.
6. Remove chatbot closers and significance inflation phrases.
7. Replace vague quantities with specific ones where the specific value is present in context.

Do NOT add: dashes, em dashes, synonym cycling, bold inline headers, rule-of-three structures, new claims.

### Step 5 — Output

**File input:**
Show the full rewritten text in a code block labeled `humanized`, then ask via AskUserQuestion:
```
question: "Write humanized version to <file-path>?"
header: "humanize-en · Write"
options:
  - label: "Write file"
    description: "Overwrite <file-path> with the humanized version"
  - label: "Show diff only"
    description: "Display a line diff — do not write"
  - label: "Discard"
    description: "Keep the original file unchanged"
```
Write only after explicit "Write file" click.

**Inline text input:**
Output the rewritten text in a code block. No write prompt.

### Step 6 — Optional double-pass (texts > 500 words)

After Step 5, if the text was > 500 words, offer:
"Run a second pass to catch remaining rhythm and structure issues? (~20s extra)"
If yes: re-run Steps 3-4 on the output and return the result.

---

## Quick reference (from rules.md)

**Never use:** delve, tapestry, testament (figurative), leverage (verb), foster, showcase, underscore (verb), pivotal, groundbreaking (figurative), vibrant (figurative), nestled, robust (overused), seamless, cutting-edge, state-of-the-art

**Never open a paragraph with:** Additionally, Moreover, Furthermore, In conclusion, It is worth noting, It should be noted, Importantly, Notably

**No dashes or em dashes:** zero tolerance. Replace every `-` or `—` used as a sentence connector with a comma or period.

**Comments:** one line max, no obvious remarks, no multi-line blocks.

**Voice:** "The system saves the file" not "The file is saved"; "is" not "serves as"

**Commit subject:** imperative, ≤72 chars, no period, no "This commit adds…"
