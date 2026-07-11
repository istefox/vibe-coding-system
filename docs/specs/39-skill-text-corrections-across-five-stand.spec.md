# SPEC — Skill text corrections across five standalone skills

Source: GitHub issue #39

## Objectives
1. Fix six instruction-layer defects (audit findings 3.1, 3.17–3.21) across claude-md-generator, prompt-builder, git-repo-init, swiftui-pro, and find-skills — each one makes a model behave wrongly on a realistic request.

## Scope
In (files vendored or refreshed by earlier roadmap issues, under `staging/plugin/skills/`):
1. `claude-md-generator/SKILL.md:13`: instructs writing a root CLAUDE.md directly, while concept-to-code Branch-B demands CLAUDE.md.proposed only (Gate-3 mv fails, file lands without HITL review). Fix: write to the output path given by the caller, defaulting to CLAUDE.md; never touch CLAUDE.md when invoked from the chain.
2. `prompt-builder/SKILL.md:3`: NEGATIVE clause routes to two skills that do not exist (vibrofer-perplexity-prompt, skill-creator). Fix: describe the exclusions in plain terms without naming ghost skills.
3. `git-repo-init/SKILL.md:58`: step 9 instructs `gh repo view --web` then retracts it mid-sentence. Fix: print the URL only, never open a browser. Keep the skill's Italian.
4. `git-repo-init/SKILL.md:48`: Fase 5 mandates first commit and push with no further questions, contradicting the HITL-before-commit-and-push invariant in both CLAUDE.md files. Fix: insert one recap gate (path, visibility, files, remote; Approve or Abort) between scaffolding and the first commit, honoring the recommended-option convention. Keep Italian.
5. `swiftui-pro/SKILL.md:29`: asserts iOS 26 default deployment target and Swift 6.2, fighting the global baseline (Swift 6, iOS 17+) and git-repo-init's scaffold constants. Fix: add a scoping line, respect the project's declared target and Swift version; newer defaults apply only when the project declares none.
6. `find-skills/SKILL.md:3`: triggers on any how-do-I question, overlapping virtually every installed skill. Fix: narrow to explicit skill-discovery intent and add a NEGATIVE clause for questions answerable directly or covered by an installed skill.

Out:
- Any file under `~/.claude`.
- Behavior/scripts of these skills beyond the cited text.

## Stack
Markdown SKILL.md files (frontmatter + prose); docs-ci (markdownlint, links).

## Architecture
Six edits across five skill directories in `staging/plugin/skills/`.

## Data model
None.

## API / Interfaces
claude-md-generator gains an explicit output-path contract (caller-provided path, `.proposed` when called from concept-to-code).

## UI flows
git-repo-init Fase 5: exactly one HITL recap gate (path, visibility, files, remote; Approve or Abort, recommended-option convention) between scaffolding and first commit.

## Edge cases
- claude-md-generator invoked standalone (no caller path): defaults to CLAUDE.md; invoked from the chain: writes CLAUDE.md.proposed and never touches CLAUDE.md.
- git-repo-init and prompt-builder are Italian-language skills: fixes keep their language conventions.
- swiftui-pro on a project with a declared target: project declaration wins; newer defaults only when none declared.

## Success criteria
- [x] Each frontmatter description still parses and stays within its skill's language conventions
- [x] claude-md-generator explicitly supports the .proposed contract when called from concept-to-code
- [x] git-repo-init Fase 5 contains exactly one HITL gate before the first commit, and no browser-opening instruction survives
- [x] No ghost skill names remain in any NEGATIVE clause
- [x] No file under `~/.claude` modified
