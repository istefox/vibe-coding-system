---
name: research-prompt
description: >
  Write a single self-contained paragraph that briefs a researcher — human or AI — on one research
  question, with numbered sub-questions, a source hierarchy, and a fixed per-finding output format.
  Use when the user wants a research brief, a "deep research prompt", a one-paragraph task for a
  researcher, or asks "what should we look for". Differentiator vs `prompt-builder` (optimizes a
  prompt for an LLM) and `interview-driver` (extracts requirements into a SPEC): this produces a
  research brief for someone who has never heard of the project.
disable-model-invocation: true
---

# Research prompt

## Provenance

Adapted from the `research-prompt` skill in `github.com/davidondrej/skills` (David Ondrej, MIT).
The methodology is his, nearly verbatim. Changed here: the execution step routes to this system's
`researcher` sub-agent instead of a third-party paid research API.

## Goal

Turn a vague research need into ONE self-contained paragraph that a researcher with zero prior
knowledge of the project can act on with zero back-and-forth.

## Rules

- **One paragraph.** No headers and no bullet list in the deliverable itself.
- **Brief the job, not the topic.** Give search handles: timeframe, ranking, source type, decision
  logic. Not just a subject.
- **Assume zero prior knowledge.** Open by explaining, in plain English, what the project is, why it
  exists, and the current situation.
- **Lead with the goal and the decision.** Right after the explainer, state the single question the
  research must answer and the decision it informs.
- **Embed all context.** Names, dates, product, prior known facts, constraints. The researcher must
  not need to ask anything or guess anything.
- **Number the sub-questions inline** (1, 2, 3…) so coverage is explicit. Keep to 3–6. One mission
  per prompt; do not cram unrelated questions together.
- **State constraints.** What to include, what to avoid.
- **Source hierarchy.** Prefer primary sources: official docs, source repositories, papers, filings,
  changelogs. Forums, X, and Reddit are weak signal only, never factual proof.
- **Contradiction handling.** If sources conflict, separate confirmed fact from inference from
  unresolved uncertainty. Never force a fake consensus. Flag low-confidence claims for verification.
- **Define done.** Do not stop at the first plausible answer. Corroborate each key claim against
  multiple independent primary sources where they exist; where sources are scarce, say so explicitly
  instead of padding. Continue until every numbered sub-question meets that bar.
- **Gap round before finishing.** Require a self-critique pass: list gaps, contradictions, and any
  single-source claims, then run another round of searches to close them. Repeat until clean.
- **Constrain the output hard, the method loosely.** Be strict about the deliverable; leave the
  search path flexible.
- **Fix the format per finding:** source link, the specific claim, and a one-line "why it matters".
- Verifiable, citable facts only. No opinions.
- **Last sentence:** instruct the researcher to write everything into a single markdown file.

## Process

1. Pull context from the project files and the conversation — dates, names, known facts, audience,
   end use. Write a one- or two-sentence plain-English explainer for a reader who knows nothing.
2. Identify the ONE question the research answers.
3. Draft 3–6 numbered sub-questions that fully cover it.
4. Add the include/avoid constraints and the per-finding output format.
5. Compress to one clean paragraph. Cut filler.

## Template

> [One or two plain-English sentences: what the project is, why it exists, the current situation.]
> Research [TOPIC + key identifying facts] to answer one question: [THE QUESTION] — for [DECISION /
> END USE]. Find: (1) …; (2) …; (3) …; (4) …. [Constraints: include X, avoid Y.] Prefer primary
> sources; treat forums and social media as weak signal only; if sources conflict, separate fact from
> inference and flag what needs verification. Do not stop at the first plausible answer: corroborate
> each key claim against multiple independent primary sources where they exist, and say so explicitly
> where they do not, continuing until every numbered question meets that bar. Before finishing, run a
> self-critique pass — list gaps, contradictions, and any single-source claims, then search again to
> close them, repeating until clean. For each point give the source link, the specific claim, and a
> one-line "why it matters". No marketing language: verifiable, citable facts only. Write everything
> into a single detailed markdown file.

## Executing the prompt

Hand the finished paragraph to the `researcher` sub-agent, which has WebSearch, WebFetch, and
context7 and returns a citation-backed brief rather than an essay:

```
Use the researcher agent with this brief: <the paragraph>
```

The same paragraph works unchanged for a human researcher or for any deep-research product. That
portability is the point of writing it as one self-contained block.
