---
name: find-skills
description: Use this skill only when the user explicitly asks to find, search for, or install a new agent skill, using phrasing like "find a skill for X", "is there a skill that can...", "search skills for X", "npx skills find X", "install a skill for X". Do NOT use for general "how do I do X" questions, for requests answerable directly without a new skill, or when an already-installed skill already covers the request.
---

# Find Skills

This skill helps you discover and install skills from the open agent skills ecosystem.

## When to Use This Skill

Use this skill only when the user explicitly asks to find, search for, or install a skill:

- "find a skill for X", "is there a skill that can…", "search skills for X"
- "npx skills find X", "install a skill for X", "add the X skill"
- Asks what skills exist for a domain, or how to browse or install one

**Do NOT use this skill** when the user:

- Asks how to do something, or asks you to do it. "How do I make my React app faster?" is a request
  for help with React, not a request to go shopping for a skill. Answer it.
- Asks whether you can do something. Say whether you can.
- Wants a task that an already installed skill covers — use that skill, do not go looking for
  another one.
- Mentions a domain in passing. Interest in testing is not a request to install a testing skill.

The distinction is the user's intent, not the topic. Almost every request touches some domain that
has a skill somewhere; that is not a reason to search. Reach for this skill when acquiring a skill
*is* the thing being asked for.

## What is the Skills CLI?

The Skills CLI (`npx skills`) is the package manager for the open agent skills ecosystem. Skills are modular packages that extend agent capabilities with specialized knowledge, workflows, and tools.

**Key commands:**

- `npx skills find [query]` - Search for skills interactively or by keyword
- `npx skills add <package>` - Install a skill from GitHub or other sources
- `npx skills check` - Check for skill updates
- `npx skills update` - Update all installed skills

**Browse skills at:** https://skills.sh/

## How to Help Users Find Skills

### Step 1: Understand What They Are Looking For

From the user's search request, identify:

1. The domain they named (e.g., React, testing, design, deployment)
2. The capability they want a skill to provide (e.g., writing tests, creating animations,
   reviewing PRs)
3. Whether an already installed skill covers it — if one does, say so and stop here

### Step 2: Check the Leaderboard First

Before running a CLI search, check the [skills.sh leaderboard](https://skills.sh/) to see if a well-known skill already exists for the domain. The leaderboard ranks skills by total installs, surfacing the most popular and battle-tested options.

For example, top skills for web development include:
- `vercel-labs/agent-skills` — React, Next.js, web design (100K+ installs each)
- `anthropics/skills` — Frontend design, document processing (100K+ installs)

### Step 3: Search for Skills

If the leaderboard doesn't cover the user's need, run the find command:

```bash
npx skills find [query]
```

For example:

- "is there a skill for React performance?" → `npx skills find react performance`
- "find me a skill for PR reviews" → `npx skills find pr review`
- "install something that writes changelogs" → `npx skills find changelog`

Note what these have in common: the user is asking for a *skill*, not for the work. "How do I make
my React app faster?" belongs in the Do-NOT list above — answer it directly instead.

### Step 4: Verify Quality Before Recommending

**Do not recommend a skill based solely on search results.** Always verify:

1. **Install count** — Prefer skills with 1K+ installs. Be cautious with anything under 100.
2. **Source reputation** — Official sources (`vercel-labs`, `anthropics`, `microsoft`) are more trustworthy than unknown authors.
3. **GitHub stars** — Check the source repository. A skill from a repo with <100 stars should be treated with skepticism.

### Step 5: Present Options to the User

When you find relevant skills, present them to the user with:

1. The skill name and what it does
2. The install count and source
3. The install command they can run
4. A link to learn more at skills.sh

Example response:

```
I found a skill that might help! The "react-best-practices" skill provides
React and Next.js performance optimization guidelines from Vercel Engineering.
(185K installs)

To install it:
npx skills add vercel-labs/agent-skills@react-best-practices

Learn more: https://skills.sh/vercel-labs/agent-skills/react-best-practices
```

### Step 6: Offer to Install

If the user wants to proceed, you can install the skill for them:

```bash
npx skills add <owner/repo@skill> -g -y
```

The `-g` flag installs globally (user-level) and `-y` skips confirmation prompts.

## Common Skill Categories

When searching, consider these common categories:

| Category        | Example Queries                          |
| --------------- | ---------------------------------------- |
| Web Development | react, nextjs, typescript, css, tailwind |
| Testing         | testing, jest, playwright, e2e           |
| DevOps          | deploy, docker, kubernetes, ci-cd        |
| Documentation   | docs, readme, changelog, api-docs        |
| Code Quality    | review, lint, refactor, best-practices   |
| Design          | ui, ux, design-system, accessibility     |
| Productivity    | workflow, automation, git                |

## Tips for Effective Searches

1. **Use specific keywords**: "react testing" is better than just "testing"
2. **Try alternative terms**: If "deploy" doesn't work, try "deployment" or "ci-cd"
3. **Check popular sources**: Many skills come from `vercel-labs/agent-skills` or `ComposioHQ/awesome-claude-skills`

## When No Skills Are Found

If no relevant skills exist:

1. Acknowledge that no existing skill was found
2. Offer to help with the task directly using your general capabilities
3. Suggest the user could create their own skill with `npx skills init`

Example:

```
I searched for skills related to "xyz" but didn't find any matches.
I can still help you with this task directly! Would you like me to proceed?

If this is something you do often, you could create your own skill:
npx skills init my-xyz-skill
```
