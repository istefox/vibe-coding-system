# humanize-en: Writing Rules Reference

Style rules for English prose. Apply in full when humanizing text.
**Never change facts, data, names, paths, versions, or function names.**

---

## Vocabulary: never use

These words are AI tells. Replace with plain alternatives or restructure the sentence.

```
delve, delving
tapestry (abstract)
landscape (abstract, e.g. "the AI landscape")
testament (as in "a testament to")
leverage (as a verb)
foster, fostering
showcase, showcasing
underscore (as a verb, e.g. "this underscores")
pivotal
groundbreaking (figurative)
vibrant (figurative)
nestled
robust (overused)
seamless
cutting-edge
state-of-the-art
```

Plain alternatives: "explore" not "delve into", "shows" not "showcases", "use" not "leverage",
"key" or "critical" not "pivotal", "supports" or "builds" not "fosters".

---

## Sentence openers: never start a paragraph with

```
Additionally,
Moreover,
Furthermore,
In conclusion,
It is worth noting that
It should be noted that
Importantly,
Notably,
```

Alternatives: restructure the sentence, use a plain connective ("Also," is fine in moderation),
or start with the subject directly.

---

## Structural patterns: avoid

- **Rule of three:** "innovation, inspiration, and insights" → use the natural count, not three for rhythm.
- **Synonym cycling:** pick one word and repeat it; do not cycle synonyms for variety.
- **Inline bold headers in bullets:** `**Performance:** The app runs faster` → convert to plain prose.
- **No dashes or em dashes:** never use `-` or `—` as sentence connectors or list separators. Use a comma or period instead. Zero tolerance, remove every instance.
- **Generic positive endings:** "The future looks bright" → end with a specific fact.
- **Chatbot artifacts:** "I hope this helps!", "Let me know if you have questions", "Great question!" → remove entirely.
- **Hedging clusters:** "could potentially possibly", "it may be argued that" → state the claim directly.
- **Significance inflation:** "marking a pivotal moment", "testament to", "underscores its vital role" → replace with specific facts.

---

## Length: keep it tight

Match length to the medium and cut anything that does not earn its place.

- Forum, Reddit, or HN comment: aim for 150 words and 3 short paragraphs. Lead with the answer.
- Forum or Reddit post body: 250 words.
- PR description or issue comment: 200 words.
- Changelog or release-note entry: 120 words per item.
- README section: no hard cap, but prefer the shortest complete version.

Procedural answers (numbered recovery or setup steps) may run past the comment target, but keep each step to one or two sentences. When a draft runs long, cut content. Do not add a closing paragraph that restates the opening, since that summary tail is the most common wall-of-text tell.

---

## Voice: apply

- **Active voice:** name the actor. "The system saves the file" not "The file is saved by the system."
- **Short sentences are fine.** Mix lengths deliberately. A two-word sentence after a complex one lands hard.
- **Use is / has / does:** "Gallery 825 is the main space" not "Gallery 825 serves as the main space."
- **Opinions are allowed:** "This approach works well because X" not neutral hedging.
- **Specific over vague:** "3 endpoints" not "several endpoints"; "fixed in v2.3" not "recently fixed."

---

## Comments and annotations: apply

- **One line max:** inline comments (`//`, `#`, `<!--`) must fit on a single line. No multi-line comment blocks.
- **No obvious remarks:** don't restate what the code does; only note the why when it's non-obvious.
- **No trailing commentary:** don't add "see above", "as mentioned", "note that" padding.

---

## Commit messages: specific rules

- Imperative mood: "Add retry logic" not "Added retry logic" or "Adding retry logic."
- Subject line ≤ 72 chars.
- No period at end of subject line.
- No AI openers: "This commit adds…", "Here we introduce…" → start with the verb.
- Body (if present): factual, no significance inflation, no "This PR improves…"

---

## Scope

Apply to: README, PR descriptions, issue comments, changelogs, release notes, blog posts,
forum posts, commit bodies, ADR rationale sections, doc inline prose.

Do NOT apply to: source code logic, variable names, function signatures, JSON/YAML/TOML config,
auto-generated files, linter pragmas, inline `# type: ignore`.

Mixed Italian/English files: apply rules only to English paragraphs.
