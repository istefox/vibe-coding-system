# ADR-0040 — Narrowing humanize-en to outside-audience publication

**Status:** Accepted
**Date:** 2026-07-24
**Author:** istefox
**Supersedes:** none
**Amends:** ADR-0015 (`humanize-en-chain-integration`) — removes Gate 0c, Gate 5.5 and commit
Step 3.5, retires the `post-md-tells-hint.sh` hook, and narrows the `prompt-en-prose-detect.sh`
trigger. The skill itself, its rules file and `detect-ai-tells.sh` are unchanged.
**Related:**

- ADR-0015 — the integration this ADR narrows. Its reasoning is not wrong, its scope was
- ADR-0027 (`31-c2c-bsd-slug-autopilot-gates`) — established that a gate written but structurally
  unreachable is a defect, which is the argument for removing Gate 5.5 rather than defaulting it off
- ADR-0034 (`38-hook-hardening`) — the dual-envelope JSON fix in `prompt-en-prose-detect.sh`,
  preserved here; also the precedent for recording a correction forward instead of editing
  historical ADRs in place
- `~/.claude/CLAUDE.md` Identity & Language — the global rule, corrected first (PR #74, `f949feb`)

## 1. Context

`humanize-en` had become the most-invoked skill in the system. Six places pushed it there, and the
skill itself was none of them.

The global rule in `~/.claude/CLAUDE.md` named "README, docs, ADR, commit messages, changelogs,
release notes" and closed with "No exceptions, including short replies". The skill's own
`description` frontmatter, which is what the model reads when deciding whether to invoke a skill,
listed the same internal artifacts. Two hooks nudged toward it: one on every user prompt mentioning
a writing target, one on every `.md` file written. Two chain integrations invoked it outright, at
`concept-to-code` Gate 5.5 and at `commit` Step 3.5.

The result was a humanize pass on ADRs, specs, plans, commit messages and repo docs. None of those
are read by a stranger. They are the working record, and rewriting them for style costs tokens and
turns while changing nothing that matters.

Two findings came out of the audit and shaped the decisions below.

**The trigger hook matched the word, not the intent.** `prompt-en-prose-detect.sh` fired on a
single regex over the prompt, so a message *about* Reddit fired it as reliably as a request to
write a Reddit post. This was observed live: the user's message asking to narrow the skill
contained "reddit" and "forum" and tripped the hook.

**`post-md-tells-hint.sh` was already a no-op.** It printed its hint as plain stdout on exit 0.
Per `code.claude.com/docs/en/hooks`, stdout on exit 0 is added to context only for
`UserPromptSubmit`, `UserPromptExpansion` and `SessionStart`; for every other event, including
`PostToolUse`, it goes to the debug log. The hint has never reached the model since deployment.

## 2. Decision

**D1. The perimeter is the audience, not the format.** `humanize-en` applies to English prose
written for an outside human audience: Reddit and HN posts, forum threads, blog posts, newsletters,
announcements, marketing copy, email to third parties. It does not apply to programming or internal
artifacts: source code, config, commit messages, PR and issue text, ADRs, specs, plans, README and
other repo docs, changelogs, release notes, chat replies, anything gitignored.

**D2. README is an internal artifact.** It is documentation read by people working on the code, not
by a stranger who found a post. This is the least obvious line in D1 and it is a judgment call, so
it is recorded as one. A public-facing project landing page would fall on the other side; a repo
README does not.

**D3. The skill's `description` frontmatter carries the perimeter, with a `NEGATIVE:` block.** That
field is the model's invocation trigger, so it matters as much as the global rule. The block follows
the form already used by `claude-md-slim` and `deep-refactor`.

**D4. Invocation is manual only.** No skill and no chain step invokes `humanize-en` automatically.
This removes commit Step 3.5 and `concept-to-code` Gate 5.5.

**D5. Gate 0c and Gate 5.5 are removed, not defaulted off.** Every artifact the chain produces is
internal under D1, so Gate 5.5 would never have a file to act on and Gate 0c would never have a
reason to enable it. Per ADR-0027, a gate that cannot fire is a defect, not a safe no-op. The
letters `0c` and `5.5` are not reused: gates are referenced by letter throughout `SKILL.md`.

**D6. Gate 5.5's state transition survives as Gate 5.6.** The gate did one thing beyond humanizing:
it transitioned `<current_step> → step_7_commit`, and no other step performs that transition.
Deleting the block wholesale would have broken the chain. Gate 5.6 keeps the transition, drops the
action and the `AskUserQuestion`.

**D7. The prompt hook requires a writing verb AND a publication target.** Two greps in AND replace
the single regex. Internal targets (README, pull request, PR description, issue, changelog, release
notes) are removed from the target list. `post` is deliberately not in the verb list: it is far more
often the noun in "a reddit post".

**D8. `post-md-tells-hint.sh` is retired,** with its PAIRS entry, its `settings.json` wiring and its
four test cases. `detect-ai-tells.sh` stays, still used by the skill and still covered by T1-T5.

**D9. `manifest-validate.sh` invariant 12 is left in place.** It is conditional on "if the humanize
field is present", so manifests written before this ADR stay valid. No migration, no schema bump.

**D10. Historical ADRs and plans are not edited.** ADR-0015, 0017, 0018, 0022, 0025, 0027, 0030, the
`docs/superpowers/plans/` files and the issue-28 spec keep their original text. The correction is
recorded forward, here. Living documentation (`SKILLS-AND-AGENTS-GUIDE.md`, `GUIDA-USO-IT.md`, the
blueprint) is updated, since it describes current state.

## 3. Alternatives considered

**Keep the gates with a false default and a narrowed file list.** Rejected per D5. It leaves a path
nothing can reach, which is the defect ADR-0027 already corrected elsewhere in this same skill.

**Fix `post-md-tells-hint.sh`'s output channel and restrict it by path.** Rejected. Switching it to
`hookSpecificOutput.additionalContext` would make a hint visible that fires on every ADR and doc,
making the problem worse before making it better. Restricting by path needs a publication-directory
convention that does not exist in any of these repos.

**Retire `prompt-en-prose-detect.sh` too.** Rejected. It costs nothing when it does not match, and a
reminder at the moment of writing has real value. Narrowing it is enough.

**Renumber commit's Step 3.6 to 3.5 after the removal.** Rejected. Other skills refer to these steps
by number; renumbering trades a small cosmetic gain for a class of stale cross-references.

## 4. Consequences

**Positive.**

- The skill fires on the text it was built for and stops firing on the working record.
- A live false positive is closed: naming Reddit in a message no longer triggers the hook.
- One hook, one script and two gates leave the system. PAIRS drops from 112 to 110 entries.
- The chain loses two gates without losing a state transition.

**Negative and accepted.**

- Removing gates is not reversible by flipping a flag. Restoring Gate 5.5 would mean restoring its
  block, its manifest field helper and its PAIRS entry.
- D2's placement of README is a judgment call, and a project whose README doubles as a public
  landing page would want the opposite.
- `humanize-en/tests/run-tests.sh` reads RED (2 failures) against the deployed tree until a human
  syncs, because it points at `$HOME/.claude/hooks/`. This is the ADR-0026 and ADR-0034 pattern and
  it is CI-dark: CI runs only `staging/plugin/scripts/tests/*.test.sh`.

**Verification.**

Full CI suite green across 14 test files after the change. `pairs-completeness` 110 PASS 0 FAIL.
`hook-hardening` 8 PASS 0 FAIL, including two new cases: an internal target stays silent, and a
publication target without a writing verb stays silent. `concept-to-code` harness 80 PASS 0 FAIL.

One pre-existing test needed an update: `concept-to-code-manifest-helpers-guards.test.sh` case D1
greps a whole sentence that ended in "proceed to step 8b.", which the Gate 0c removal renumbered to
"8c.". The expected string was updated and the assertion left identical — it still checks the
absolute PATH RULE prefix at that call site.

## 5. References

- ADR-0015 `docs/architecture/ADR-0015-humanize-en-chain-integration.md`
- ADR-0027 `docs/architecture/ADR-0027-31-c2c-bsd-slug-autopilot-gates.md`
- ADR-0034 `docs/architecture/ADR-0034-38-hook-hardening.md`
- `code.claude.com/docs/en/hooks` — exit-code and JSON output contract per hook event
- PR #74 (`f949feb`) — the global rule, corrected first
