# ADR-0035 — Skill text corrections across five standalone skills

**Status:** Accepted
**Date:** 2026-07-11
**Author:** istefox
**Supersedes:** none
**Amends:** none
**Related:**

- SPEC: `docs/specs/39-skill-text-corrections-across-five-stand.spec.md` (= `SPEC.md` at repo root,
  GitHub issue #39, confirmed byte-identical by diff before writing this ADR)
- ADR-0003 (`concept-to-code-chain`) — original `claude-md-generator` design and its Branch-B
  invocation pattern (`Skill` tool, not `Agent` tool)
- ADR-0011 (`clean-public-repo-anonymize`) — names the "additive directive conveyed in the
  dispatch prompt, not in the skill's own `SKILL.md`" pattern that `concept-to-code/SKILL.md:1796`
  explicitly says `claude-md-generator` already follows; this ADR's Finding A closes the gap that
  pattern leaves open when the skill's own text disagrees with the prompt
- ADR-0012 (`agent-memory-orchestrator-mediated`), ADR-0013
  (`native-subagent-memory-supersede-mediated`) — D5's non-regression guard on
  `claude-md-generator` (must not generate/inherit a doc-discipline rule conflicting with
  `agent-notes`); re-verified absent from the current file and not reintroduced by this ADR
- ADR-0024 (`vendor-deployed-only-skills-and-hooks`) — established `staging/` as this roadmap's
  working source of truth and `sync-to-claude.sh`'s `PAIRS` table as the incremental sync
  mechanism, plus `pairs-completeness.test.sh`'s self-test-then-real-check design this ADR reuses
  unmodified
- ADR-0025 (`refresh-stale-staging-copies`) — §2.3/§3.2/§4 Negative explicitly flagged, by name,
  that `claude-md-generator/SKILL.md` had no `PAIRS` entry and that "issue #39, which already plans
  to edit `claude-md-generator/SKILL.md`, will need to add its own `PAIRS` entry (or explicitly
  accept RUNBOOK-only deployment)" — this ADR is that follow-up and chooses the former
- ADR-0027 (`c2c-bsd-slug-autopilot-gates`), ADR-0028 (`manifest-helpers-guards`), ADR-0030
  (`scope-guards`) — structural precedent this ADR reuses directly (multi-finding issue, one
  shared hermetic test file, lettered sections, `ok`/`bad`/`PASS`/`FAIL` idiom)
- `staging/plugin/skills/concept-to-code/SKILL.md:459-479` — Branch B's existing dispatch prompt
  ("Generate `CLAUDE.md.proposed` from scratch... Do NOT overwrite... only write the `.proposed`
  file"), the caller-side contract `claude-md-generator`'s own text must now match
- `docs/plugins-and-mcp-catalog.md:21` — verifies `skill-creator`'s real status (a cataloged
  marketplace plugin, not a `staging/plugin/skills/` repo-native skill)
- The five files this ADR patches: `staging/plugin/skills/claude-md-generator/SKILL.md`,
  `staging/plugin/skills/prompt-builder/SKILL.md`, `staging/plugin/skills/git-repo-init/SKILL.md`,
  `staging/plugin/skills/swiftui-pro/SKILL.md`, `staging/plugin/skills/find-skills/SKILL.md`
- `staging/sync-to-claude.sh`, `staging/plugin/scripts/tests/pairs-completeness.test.sh`,
  `.github/workflows/docs-ci.yml`
- Implementation plan: `docs/superpowers/plans/2026-07-11-39-skill-text-corrections.md`

---

## 1. Context

Issue #39 names six instruction-layer defects (the audit range SPEC.md and the GitHub issue both
cite as "3.1, 3.17 to 3.21" — no per-defect sub-number mapping is available in this repository or
in the issue body itself, so this ADR does not invent one; it cites the range as SPEC states it and
otherwise refers to each defect by file and current line) across five skills vendored or refreshed
by earlier roadmap issues. Each is an instruction-layer bug: the skill's own text, not its
scripts or scaffolding, makes a model behave wrongly on a realistic request. All six were
re-verified against the current file state (not assumed) before this ADR was written; the exact
line numbers SPEC.md cites all matched on inspection.

### Finding A — `claude-md-generator/SKILL.md:13`, hardcoded "root CLAUDE.md" conflicts with the chain's own dispatch prompt

The file's generation instruction reads, in full: ``Generate a root `CLAUDE.md` that is **lean and
Anthropic-compliant**:``. This is unconditional — nothing in the file's 16 lines makes the output
path depend on how the skill was invoked.

`concept-to-code/SKILL.md`'s Branch B (greenfield CLAUDE.md, lines 459-479) already dispatches this
skill with an explicit, opposing directive:

```
Generate CLAUDE.md.proposed from scratch at <project-root>/CLAUDE.md.proposed.
Do NOT overwrite <project-root>/CLAUDE.md — only write the .proposed file.
```

`concept-to-code/SKILL.md:1796` frames this as the established pattern for this exact skill:
"invoked as-is in Step 3 (additive directive conveyed in the prompt template, not in
`claude-md-generator`'s `SKILL.md`)" — the same "additive directive" idiom ADR-0011 names for
`clean-public-repo`. The idiom works when the skill's own baked text is silent on the question the
directive answers. Here it is not silent: it flatly instructs "a root `CLAUDE.md`," a direct,
same-turn conflict between the skill's own instructions and the caller's dispatch prompt for every
single Branch-B invocation, not an edge case. SPEC.md's own characterization of the resulting
failure mode: "the Gate-3 `mv` fails and the file lands without HITL review" — Gate 3's approve
action is `mv CLAUDE.md.proposed CLAUDE.md`; if `claude-md-generator` already wrote directly to
`CLAUDE.md` (following its own text over the prompt), that move has no source file, or worse,
`CLAUDE.md` is already overwritten before the human ever sees Gate 3's diff.

`claude-md-generator/SKILL.md` also carries no `PAIRS` entry in `sync-to-claude.sh` today (verified
by reading the file before writing this ADR — grep for `claude-md-generator` against the block
between `PAIRS="` and the closing `"` returns nothing). ADR-0025 §2.3/§3.2 flagged this by name as a
gap left open for this issue to close ("Issue #39, which already plans to edit
`claude-md-generator/SKILL.md`, will need to add its own PAIRS entry (or explicitly accept
RUNBOOK-only deployment)").

### Finding B — `prompt-builder/SKILL.md:3`, NEGATIVE clause names two skills absent from this system

The frontmatter description's closing sentence reads: `NON usare per ricerche Perplexity Vibrofer
(usa vibrofer-perplexity-prompt) né per creare skill (usa skill-creator).` Both parenthetical
skill names were checked against the actual system, not assumed broken:

- `vibrofer-perplexity-prompt` appears nowhere in this repository outside SPEC.md, the GitHub
  issue, and `prompt-builder/SKILL.md` itself (grepped across `staging/` and `docs/`). It is not a
  `staging/plugin/skills/` directory, not a catalog entry, not referenced by any other skill. Fully
  fictional.
- `skill-creator` **does** exist, but not as a repo-native staging skill: `docs/plugins-and-mcp-catalog.md:21`
  lists it as an installed marketplace plugin ("`skill-creator` | 42be4c4 | Meta | Crea nuovi
  skill"), a general-purpose Claude Code plugin unrelated to this repository's own
  `staging/plugin/skills/` tree and not guaranteed present in every environment this repo's skills
  are deployed to.

Both names are "ghost" from `prompt-builder`'s own repository's perspective: routing a NEGATIVE
clause to a skill this repo does not vendor, ship, or control the presence of, is a broken
instruction-following trap regardless of whether that name happens to resolve in one particular
user's marketplace-plugin set.

### Finding C — `git-repo-init/SKILL.md:48,58`, Fase 5 asserts "no further questions" then contradicts itself on opening a browser

Two defects share one section (`## Fase 5 - Esecuzione`, current lines 46-58):

1. **Line 48**: `Ordine fisso, nessuna domanda aggiuntiva:` ("fixed order, no further questions") —
   asserted immediately before a nine-step sequence that includes the first commit (step 6) and,
   conditionally, the first push (step 7). This directly contradicts the HITL-before-commit-and-push
   invariant both `~/.claude/CLAUDE.md` and this repository's own `CLAUDE.md` state
   unconditionally ("HITL gate always before: commit, push, deploy, DB schema changes, permanent
   deletions"). No gate of any kind exists anywhere in Fase 5 today.
2. **Line 58**: ``9. Verifica: `git log --oneline` e (se remoto) `gh repo view --web` NO - non
   aprire il browser; stampa solo l'URL della repo.`` — the step instructs `gh repo view --web`
   (which opens a browser) and then immediately retracts that instruction mid-sentence with a bare
   "NO," leaving a single step that says two contradictory things about the same action in the same
   breath. A model executing this literally could go either way.

### Finding D — `swiftui-pro/SKILL.md:29`, unconditional iOS 26/Swift 6.2 defaults fight a project's own declared target

`## Core Instructions` opens with: `- iOS 26 exists, and is the default deployment target for new
apps.` followed by `- Target Swift 6.2 or later, using modern Swift concurrency.` Both are stated as
unconditional facts about every project this review pass touches, not defaults scoped to a project
that has not declared its own target. This directly fights two things already in this system: the
user's own global baseline (`~/.claude/CLAUDE.md`: "Swift 6, modern patterns... iOS 17+") and
`git-repo-init`'s own Swift/Xcode scaffolding path (`references/swift-xcode-setup.md`, not edited by
this ADR — out of SPEC's cited scope), which sets concrete target/Swift-version values per project at
scaffold time. `swiftui-pro` is a third-party-authored skill vendored into this repository (frontmatter
`license: MIT`, `metadata.author: Paul Hudson`), confirmed unrelated to `~/.claude` write scope for
this ADR the same way the four repo-native skills are.

### Finding E — `find-skills/SKILL.md:3`, trigger overlaps virtually every installed skill

The frontmatter description reads, in full: `Helps users discover and install agent skills when they
ask questions like "how do I do X", "find a skill for X", "is there a skill that can...", or express
interest in extending capabilities. This skill should be used when the user is looking for
functionality that might exist as an installable skill.` The first clause ("how do I do X") is not a
skill-discovery-specific pattern; it is the shape of nearly every task request a user could make to
any installed skill in this system. No NEGATIVE clause exists to route away from requests already
answerable directly or already covered by an installed skill — every other multi-clause skill
description in this repository that has overlap risk carries one (`review-triage-fix`,
`prompt-builder`, `concept-to-code`'s own scoping bullets), `find-skills` does not.

### Cross-check — what else was searched and confirmed compatible or out of scope

Before writing the Decision below, every other place in the codebase referencing these five files
was searched, not assumed clean (repeats, for this issue, the discipline ADR-0028/0029/0030
established):

- `staging/plugin/scripts/tests/*.test.sh` (all 12 files) and `staging/plugin/skills/*/tests/`:
  grepped for `claude-md-generator`, `prompt-builder`, `git-repo-init`, `swiftui-pro`,
  `find-skills` — zero hits. None of the five files this ADR patches is referenced, asserted
  against, or fixtured by any existing hermetic test. This ADR's new test file is a pure addition
  with zero pre-existing anchors at risk.
- `sync-to-claude.sh`'s `PAIRS` table: `prompt-builder`, `git-repo-init`, `swiftui-pro`, and
  `find-skills` **already** carry an entry each (confirmed by reading the file directly); only
  `claude-md-generator` does not. This ADR's Finding A is therefore the only one of the six that
  needs a `PAIRS` change.
- `docs/GUIDA-USO-IT.md`, `docs/GUIDA-CREARE-PROGETTO.md`, `docs/vibe-coding-system.md`: all
  describe `claude-md-generator`'s role at a level ("generates project CLAUDE.md") that does not
  assert a specific hardcoded output path; none needs reconciling the way ADR-0030's
  `GUIDA-USO-IT.md` scope-guard paragraphs did.
- `staging/plugin/skills/project-init/SKILL.md:6,34` references `claude-md-generator` for
  richer, SPEC/ADR-aware output; both mentions are path-agnostic prose, confirmed compatible, not
  edited.
- `research-prompt/SKILL.md` (a real, existing repo-native skill) was checked as a candidate
  real-name substitute for the removed `vibrofer-perplexity-prompt` reference and found to be a
  generic research-brief-writing skill with no Perplexity- or Vibrofer-specific scope — confirmed
  not a correct substitute (see §3.3).
- The claude-md-generator D5 non-regression guard (ADR-0012 Task 8: the file must not
  generate/inherit a doc-discipline rule mentioning `agent-notes`) was re-checked: `grep -q
  "agent-notes"` against the current staging file returns no match, exactly as before. Finding A's
  edit is scoped to the output-path contract only; it does not touch, add, or remove anything
  related to that separate guard.

---

## 2. Decision

Fix all six findings in place, in their existing five files, with no new skill, no new hook, no
manifest schema change, and no new global infrastructure. One shared hermetic test file
(`staging/plugin/scripts/tests/skill-text-corrections.test.sh`), five lettered sections (A-E, one
per file), follows the established multi-finding convention (ADR-0027/0028/0030). `sync-to-claude.sh`
gains exactly one new `PAIRS` line (Finding A).

### 2.1 Finding A — caller-provided output-path contract, plus the file's first `PAIRS` entry

Replace the unconditional generation instruction (current line 13) with an explicit contract that
matches Branch B's already-existing dispatch prompt instead of conflicting with it:

```
Write to the output path given by the caller (for example `<project-root>/CLAUDE.md.proposed` when
invoked from the concept-to-code chain); if the caller gives no path, default to
`<project-root>/CLAUDE.md`. Never touch `CLAUDE.md` directly when invoked from the chain. Write only
to the `.proposed` path the chain provides.

Generate a project memory file at that output path, **lean and Anthropic-compliant**:
```

The `.proposed`-vs-default split is exactly SPEC's own fix language ("write to the output path
given by the caller, defaulting to CLAUDE.md; never touch CLAUDE.md when invoked from the chain")
and exactly matches the two edge cases SPEC.md's own "Edge cases" section names: standalone
invocation (no caller path → defaults to `CLAUDE.md`, preserving today's behavior for a user
running `/skill claude-md-generator` directly) and chain invocation (caller path given → write
there, never touch `CLAUDE.md`). Lines 14-16 (the "lean and Anthropic-compliant" bullet list) are
untouched apart from the lead-in sentence now reading "Generate a project memory file at that
output path" instead of "Generate a root `CLAUDE.md`" — nothing about *what* gets generated changes,
only *where* it is written.

`sync-to-claude.sh`'s `PAIRS` block gains one new line, appended at the end (matching the
established append-only convention — ADR-0025 §2.3 added `goal-loop`/`research-prompt` the same
way, at the end of the block):

```
plugin/skills/claude-md-generator/SKILL.md|skills/claude-md-generator/SKILL.md
```

`pairs-completeness.test.sh`'s existing self-test-then-real-check design (ADR-0024) needs no code
change to cover this: the real-check phase already iterates every line in the block, and the new
source file (`staging/plugin/skills/claude-md-generator/SKILL.md`) already exists, so the addition
is a real, exercised, passing structural fact the moment it lands — `PAIRS` grows from 108 to 109
entries (counted directly from the file before writing this ADR).

### 2.2 Finding B — plain-terms exclusions, no skill names

Replace the closing sentence of the frontmatter description (current line 3) with:

```
NON usare per ricerche Perplexity Vibrofer né per creare una nuova skill da zero.
```

Everything else on line 3 (the trigger-phrase list, the "Trigger;" marker, the confidence/technique
description) is untouched — this is a one-sentence, minimal, surgical replacement, matching SPEC's
own instruction to describe the exclusions "in plain terms" rather than substitute different names.

### 2.3 Finding C — one recap HITL gate between scaffolding and the first commit, plus a browser-free verify step

Rewrite `## Fase 5 - Esecuzione` (current lines 46-58) as a ten-step sequence (was nine), inserting
exactly one new step 6 immediately after the `clean-public-repo` audit invocation (current step 5,
unchanged) and immediately before the first commit (current step 6, renumbered 7):

```
Ordine fisso, con un solo gate di conferma prima del primo commit (step 6):

1. `mkdir` nella posizione canonica (vedi "Posizione del progetto") e `git init -b main`
2. Genera i file dello scaffolding scelto. Per .gitignore usa i template ufficiali GitHub (`gh repo gitignore view <Template>` o https://github.com/github/gitignore). Per la licenza usa il testo ufficiale (gh o choosealicense.com) con anno corrente e nome utente.
3. **Se stack = Swift**: esegui il setup Tuist/Xcode da `references/swift-xcode-setup.md` (manifesti, sorgenti skeleton, `tuist generate`, build + test verde). Per gli altri stack genera la struttura sorgenti standard.
4. Genera `CLAUDE.md` e `PROJECT_BRIEF.md` dai template in `assets/`, compilati con TUTTE le risposte del wizard. Non lasciare placeholder vuoti. Per Swift usa il blocco Commands e il working agreement indicati in `references/swift-xcode-setup.md`.
5. **Se visibilita = public e l'utente ha accettato l'audit**: invoca la skill `clean-public-repo` ORA, prima del primo commit/push.
6. **Gate di conferma (HITL)**: prima di procedere, mostra un riepilogo (percorso locale, visibilita, elenco file generati, remote che verra creato se applicabile) e usa AskUserQuestion con due opzioni: "Approva (Recommended)" per procedere con commit e push, "Interrompi" per fermarti qui senza commit ne push. Assegna "(Recommended)" ad "Approva" solo se lo scaffolding e pulito (nessun avviso residuo dall'audit `clean-public-repo`, nessuna directory preesistente sovrascritta); in caso contrario raccomanda "Interrompi" e spiega perche in una riga. Su interruzione: la repo locale resta cosi com'e, nessun commit, nessun push.
7. Primo commit, sempre conventional: `chore: initial project scaffolding`
8. Se gh disponibile: `gh repo create <nome> --<visibilita> --source . --push --description "<descrizione>"`
9. Se richiesta branch protection: applicala via `gh api` dopo il push.
10. Verifica: `git log --oneline` e, se remoto, stampa l'URL della repo con `gh repo view --json url -q .url` (mai `--web`, mai aprire il browser).
```

Three properties of this rewrite are load-bearing:

1. **Exactly one gate** — SPEC's own success criterion is "exactly one HITL gate before the first
   commit," not "a gate somewhere." The new step 6 is the only new content; steps 1-5 and the
   renumbered 7-10 are byte-identical in wording to the current steps 1-5 and 6-9 (only the leading
   digit changes for 6-9→7-10).
2. **Placed after `clean-public-repo`, not before it** — the gate's own recap explicitly shows
   "elenco file generati" (the generated file list); placing it after the conditional audit means
   the recap reflects the post-audit file state, not a snapshot that the audit could still change
   out from under the user.
3. **Recommended-option convention, honestly applied** — `~/.claude/CLAUDE.md`'s own convention
   ("recommended option first... append '(Recommended)'... on safety/authorization gates the
   recommendation reflects an honest analysis... never a blind endorsement") is followed literally:
   "Approva (Recommended)" is only the recommended choice when the scaffold is actually clean; the
   new step's own text states the opposite recommendation for the opposite case ("in caso contrario
   raccomanda 'Interrompi'").

Line 58's fix is now step 10's final clause: ``stampa l'URL della repo con `gh repo view --json url
-q .url` (mai `--web`, mai aprire il browser)`` — a single, unambiguous instruction (never open a
browser, print the URL via a non-interactive `gh` invocation) replacing the self-contradicting
"instructs then retracts" sentence.

Both defects share this one file and one section, so both land in a single Fase-5 rewrite rather
than two separate patches (see §3.4 for why this is not split further).

### 2.4 Finding D — a scoping bullet, placed first, governing the specific defaults that follow

Insert one new bullet at the top of `## Core Instructions` (current line 27), before the existing
`- iOS 26 exists...` bullet (current line 29, unchanged):

```
- Respect the project's own declared deployment target and Swift version when it declares one
  (Package.swift, project.yml, Tuist manifest, Xcode project settings). iOS 26 and Swift 6.2 below
  are defaults for a project that declares none, not an override for one that does.
- iOS 26 exists, and is the default deployment target for new apps.
- Target Swift 6.2 or later, using modern Swift concurrency.
```

Every other bullet in `## Core Instructions` (UIKit avoidance, third-party frameworks, per-type file
layout, feature-driven folder structure) is untouched. Placing the scoping bullet first, rather than
appended after the two defaults it qualifies, is deliberate — see §3.5.

### 2.5 Finding E — explicit skill-discovery intent, plus a NEGATIVE clause

Replace the frontmatter description (current line 3) in full:

```
Use this skill only when the user explicitly asks to find, search for, or install a new agent
skill, using phrasing like "find a skill for X", "is there a skill that can...", "search skills for
X", "npx skills find X", "install a skill for X". Do NOT use for general "how do I do X" questions,
for requests answerable directly without a new skill, or when an already-installed skill already
covers the request.
```

This satisfies both halves of SPEC's fix instruction in one sentence pair: the opening sentence
narrows the trigger to explicit skill-discovery intent (the four example phrasings are drawn from
the skill's own body, `npx skills find` is its own literal CLI syntax already documented at
`SKILL.md:57`); the second sentence is the NEGATIVE clause, covering both exclusion classes SPEC
names by name ("questions answerable directly" and "covered by an installed skill"). The file's body
(`## When to Use This Skill`, `## Common Skill Categories`, etc.) is untouched — see §3.6 for why
this is deliberately scoped to the frontmatter line SPEC cites.

### 2.6 Test strategy

One new hermetic file, `staging/plugin/scripts/tests/skill-text-corrections.test.sh`, five lettered
sections (A-E, one per file), 24 static-anchor assertions total (A=5, B=4, C=7, D=4, E=4), reusing
the exact `ok()`/`bad()`/`PASS`/`FAIL` idiom every existing file in this directory already uses, plus
one small shared helper (`frontmatter_ok`) that all five sections call once each — a bash-only,
zero-dependency structural check (file opens with `---`, a closing `---` exists, `name:` and
`description:` both appear between them), not a real YAML parser, matching this directory's existing
"no python, no yq" discipline. Every assertion is a **static** grep/positional check against file
content; unlike ADR-0027/0028/0030's shell-logic fixes, there is no runtime behavior to
extract-and-execute here, so this file needs no `mktemp -d` fixtures and no dynamic dispatch helpers
— see §3.8 for why this ADR departs from those three ADRs' interleaved-RED/GREEN-per-section task
structure while keeping their file-format conventions.

Two sections use a **positional** assertion (grep the line number of two anchors, assert their
relative order) to directly operationalize a structural SPEC requirement that a presence/absence
check alone cannot express: Section C's gate must sit between scaffolding and the first commit, not
merely exist somewhere in the file; Section D's scoping bullet must precede the defaults it
qualifies, not merely coexist with them.

Wired into `.github/workflows/docs-ci.yml`'s explicit `shell-tests` list (append
`skill-text-corrections`, thirteenth entry) and picked up automatically by `.claude/test-cmd`'s
wildcard glob (`staging/plugin/scripts/tests/*.test.sh`, confirmed by reading the file — no edit
needed there).

---

## 3. Alternatives considered

### 3.1 Bundling six findings across five files into one ADR, one plan, one test file, one commit

- **Alt A1 — five separate ADRs/plans/commits, one per file** (six findings, but two share a file).
  **Rejected:** the upstream GitHub issue #39 already bundles all six findings under one issue and
  one `SPEC.md` (confirmed byte-identical); splitting ADR granularity finer than issue granularity
  would be inconsistent with every prior issue in this roadmap (one issue → one ADR, ADR-0024
  through ADR-0034), and would produce five small PRs for changes that share zero runtime
  dependency but do share one coherent "audit found these six instruction bugs" narrative.
- **Chosen: Alt A2 — one ADR, one plan, one shared test file with lettered sections, one commit**,
  matching SPEC.md's own single-issue framing and the ADR-0027/0028/0030 precedent for a
  multi-finding issue in this exact roadmap. Each finding's task remains independently revertible by
  file/hunk if a reviewer wants to accept some but not all six; nothing about this choice forecloses
  that.

### 3.2 Finding A — fix the skill's own text vs. rely solely on the dispatch-prompt override; and what the path-less default should be

- **Alt A3 — leave `claude-md-generator/SKILL.md` untouched; rely solely on
  `concept-to-code/SKILL.md`'s existing dispatch-prompt override.** **Rejected:** this is the status
  quo, and the status quo is the reported bug. The "additive directive... not in the skill's own
  `SKILL.md`" pattern (ADR-0011, `concept-to-code/SKILL.md:1796`) works when the skill's own text is
  silent on the question the directive answers; here the skill's own text is not silent, it is
  actively wrong ("a root `CLAUDE.md`," unconditionally), so the two instructions conflict in the
  same turn every single time Branch B invokes this skill, not in some edge case. SPEC.md
  explicitly asks to fix the skill file, not the caller.
- **Alt A4 — require the caller to always supply an explicit output path; no default, error if
  none given.** **Rejected:** breaks standalone invocation. SPEC.md's own "Edge cases" section
  requires the opposite ("claude-md-generator invoked standalone (no caller path): defaults to
  CLAUDE.md"), and `project-init/SKILL.md:6,34` already assumes direct, path-less invocation of
  `claude-md-generator` works today for projects going through the chain "with `--update`." An
  always-explicit-path requirement would regress that path for no benefit.
- **Chosen: Alt A5 — an explicit, caller-provided-output-path contract inside the skill's own
  text, defaulting to `CLAUDE.md` when the caller gives none, with an unconditional "never touch
  `CLAUDE.md` when invoked from the chain" rule.** Matches SPEC's literal fix language, closes the
  same-turn conflict Alt A3 leaves open, and preserves the standalone default Alt A4 would break.

### 3.3 Finding B — plain-terms exclusion vs. naming a real substitute skill

- **Alt B1 — replace the two ghost names with real, existing skill names that plausibly cover the
  same exclusion intent** (e.g. point "ricerche Perplexity Vibrofer" at `research-prompt`).
  **Rejected:** checked directly — `research-prompt/SKILL.md` is a generic research-brief-writing
  skill with no Perplexity- or Vibrofer-specific scope (confirmed by reading its own description).
  Pointing a NEGATIVE clause at the wrong real skill is worse than pointing it at no skill at all: it
  actively misdirects a model executing this instruction toward a skill that does not actually cover
  the excluded use case, rather than just honestly excluding the topic. No other repo-native skill is
  a closer match either (grepped `staging/plugin/skills/*/SKILL.md` descriptions for
  "perplexity"/"vibrofer" — no hits besides `prompt-builder` itself). SPEC's own fix text asks for
  plain terms, not a substitute name, for exactly this reason.
- **Chosen: Alt B2 — describe both exclusions in plain language, no skill names at all.** Matches
  SPEC exactly, does not require this repository to guarantee any particular substitute skill's
  continued existence or scope, and removes the broken-reference risk entirely rather than trading it
  for a different, harder-to-notice one.

### 3.4 Finding C — where to place the HITL gate relative to `clean-public-repo`, and whether to split the two git-repo-init defects

- **Alt C1 — insert the gate immediately after scaffolding (current step 4), before the
  `clean-public-repo` audit invocation (current step 5).** **Rejected:** the audit can still modify
  or flag files after the gate would have already shown its recap, so a user approving "the files
  I can see" at that point would be approving a snapshot the audit might still change — weaker
  guarantee than approving the final, post-audit state.
- **Chosen: Alt C2 — insert the gate immediately after `clean-public-repo` (current step 5, now
  still step 5), immediately before the first commit (now step 7).** The recap's file list reflects
  the actual, final pre-commit state; matches SPEC's own instruction ("between scaffolding and the
  first commit") without ambiguity about which side of the audit it falls on.
- **Alt C3 — fix line 58 (browser) and line 48/the gate (HITL) as two separate tasks/patches within
  the same file, to keep each finding's diff minimal and independently revertible.** **Rejected:**
  both defects live inside the same nine-line `## Fase 5` section, and fixing the gate insertion
  already requires renumbering every step from 6 onward — doing that renumbering twice (once for
  each patch) either produces an intermediate, inconsistently-numbered state or forces the second
  patch to redo the first's renumbering work. One coherent rewrite of the whole section, done once,
  is a smaller total diff and cannot leave the file in a numbering-inconsistent intermediate state.
- **Chosen: Alt C4 — one rewrite of the full `## Fase 5` section covering both defects together**
  (§2.3). Both defects are independently identifiable in the resulting diff by content (the new step
  6 for the gate, step 10's final clause for the browser fix) even though they land in one hunk.

### 3.5 Finding D — where in the bullet list the scoping rule belongs

- **Alt D1 — append the scoping bullet after the existing iOS 26/Swift 6.2 bullets, at the end of
  `## Core Instructions` or immediately following them.** **Rejected:** a reader or model processing
  the list top-to-bottom would absorb "iOS 26 is the default deployment target" as an unscoped,
  unconditional statement before ever reaching the qualifier that scopes it — weaker
  instruction-following reliability than stating the scope first. This codebase's own convention for
  governing/conditional rules is to state them before the specific rules they modify (e.g. this
  project's own `CLAUDE.md` states "Inherits global rules" before its specialization content, not
  after).
- **Chosen: Alt D2 — insert the scoping bullet first, immediately under the `## Core Instructions`
  heading, before the two defaults it qualifies.** Matches SPEC's own framing ("iOS 26/Swift 6.2
  defaults apply only when the project declares none") as a rule that governs what follows, and this
  codebase's own convention for where governing statements belong.

### 3.6 Finding E — fix the frontmatter trigger only, vs. also rewrite the body's usage rationale

- **Alt E1 — also rewrite `## When to Use This Skill`'s Step 1 bullet ("Asks 'how do I do X'...")
  and related body prose, for full internal consistency with the narrowed frontmatter trigger.**
  **Rejected for this ADR, not permanently:** SPEC's cited text is `find-skills/SKILL.md:3` only,
  and SPEC's own "Out" scope states "Behavior/scripts of these skills beyond the cited text." The
  frontmatter `description` field is what Claude Code's own skill-discovery mechanism reads to
  decide *whether* to surface/invoke a skill in the first place; the body's "When to Use This
  Skill" section is supplementary guidance read only *after* the skill has already been invoked
  deliberately. Fixing line 3 alone therefore already closes the practical defect SPEC names
  ("overlapping virtually every installed skill" — an over-*triggering* problem, which the
  frontmatter field governs). Rewriting the body as well is a materially larger, unrequested edit to
  a file this ADR is meant to patch surgically.
- **Chosen: Alt E2 — fix only the frontmatter description (line 3), leave the body untouched.**
  Closes the defect SPEC names at the layer that actually causes it; flagged explicitly in this
  ADR's Consequences/Negative as a disclosed, deliberate residual inconsistency rather than a missed
  spot, for a future issue to pick up if ever needed.

### 3.7 `PAIRS` growth scope — one new entry vs. closing the gap for all seven currently-entry-less repo-native skills

- **Alt F1 — while already editing `sync-to-claude.sh`'s `PAIRS` table for `claude-md-generator`,
  also add entries for the other six repo-native skills confirmed to still have none** (`adr-writer`,
  `code-review-checklist`, `commit`, `fastapi-react-vibe`, `interview-driver`, `swift-vibe` — ADR-0025
  §2.3's own list, minus `claude-md-generator`). **Rejected, for the same reason ADR-0025 §3.2's own
  Alternative A gave when it considered and rejected the identical broader move:** none of those six
  files is touched by SPEC.md's cited scope for issue #39; they remain reachable via
  `docs/RUNBOOK.md`'s bulk-copy disaster-recovery procedure exactly as before, so adding `PAIRS`
  entries for them is not blocked by any missing capability, only unrequested by this issue.
  Widening `PAIRS` scope beyond what an issue's own SPEC asks for is explicitly the question
  ADR-0025 punted to "a design question this issue is not positioned to answer for all seven at
  once" — issue #39 is positioned to answer it only for the one file it actually edits.
- **Chosen: Alt F2 — add exactly one new `PAIRS` entry, for `claude-md-generator`, the only one of
  the six files this issue edits that lacked one.** Matches the explicit roadmap instruction for
  this issue ("Verify which of the six files have PAIRS entries; add entries for any that need to
  reach deployment") and ADR-0025's own disclosed expectation, without deciding a broader policy
  question this issue was never scoped to answer.

### 3.8 Test harness task granularity — one combined RED task vs. interleaved RED/GREEN per section

- **Alt G1 — interleave RED and GREEN tasks per section, exactly as ADR-0027/0028/0030's plans
  do** (RED Section A, GREEN Section A, RED Section B, GREEN Section B, ...), producing ten tasks
  for five sections. **Rejected for this issue specifically:** that interleaving earns its keep in
  ADR-0027/0028/0030 because each section's RED phase has real, non-obvious execution semantics to
  pin down before the fix lands (dynamic `mktemp -d` fixtures, extract-and-execute helpers, exit-code
  edge cases like Risk A/B in ADR-0030's plan). This issue's 24 assertions are **all** static
  content/positional greps against prose files — there is no runtime behavior to extract, no fixture
  to construct, and no accidental-pass risk analogous to ADR-0030's Section C. Interleaving ten tasks
  for content that does not need per-section RED analysis would not add safety, only task-count
  overhead, working against the roadmap's own "5-7 tasks" sizing guidance for this issue.
- **Chosen: Alt G2 — one RED task writing the full file (all five sections) at once, confirming the
  genuine baseline RED pattern in a single checkpoint, followed by five GREEN tasks (one per file)
  and one final wiring/regression task — seven tasks total.** Preserves genuine TDD (the test is
  written and confirmed failing before any fix lands) without paying for interleaving structure this
  issue's static-only assertions do not need. Keeps the shared file-format conventions (`ok`/`bad`,
  lettered sections, `PASS`/`FAIL` tally) fully consistent with ADR-0027/0028/0030 — only the task
  *sequencing*, not the test *file's own structure*, differs.

---

## 4. Consequences

### Positive

- All six defects are closed with minimal, surgical, independently-identifiable edits; nothing
  beyond SPEC's cited text is rewritten in any of the five files (Finding E's body is explicitly
  left alone — §3.6 — and Finding C's two defects share one rewritten section but remain
  distinguishable in the resulting diff — §3.4).
- `claude-md-generator`'s own text is now self-consistent with `concept-to-code` Branch B's
  already-existing dispatch prompt for the first time since the chain was designed, closing the
  same-turn instruction conflict that could make Gate 3's `mv CLAUDE.md.proposed CLAUDE.md` fail, or
  let `CLAUDE.md` land without the human ever seeing the Gate 3 diff — a project-memory-integrity
  bug, not a cosmetic one, since Gate 3 is this system's sole human checkpoint on generated project
  memory for a brand-new project.
- `claude-md-generator` gains its first `PAIRS` entry ever, directly resolving the gap ADR-0025
  §2.3/§3.2/§4-Negative flagged by name for this issue, so this fix (and any future one) has a real,
  incremental, dry-run-first sync path to deployment instead of depending solely on
  `docs/RUNBOOK.md`'s bulk-copy disaster-recovery procedure.
- `prompt-builder`'s NEGATIVE clause no longer instructs a model to route around this skill toward
  two names that do not resolve inside this repository's own skill set — one fully fictional, one a
  marketplace plugin this repo does not vendor or guarantee present.
- `git-repo-init`'s Fase 5 goes from actively contradicting this system's own HITL-before-commit
  invariant ("no further questions" immediately preceding an unattended commit-and-push sequence)
  to satisfying it with one gate, honoring the recommended-option convention honestly (the
  recommendation is conditioned on the scaffold actually being clean, never a blind default). The
  same rewrite also removes a genuinely self-contradicting instruction (`gh repo view --web` /
  "NO — don't open the browser" in the same sentence) that left real behavior ambiguous.
- `swiftui-pro`'s greenfield defaults (iOS 26, Swift 6.2) can no longer override a project's own
  already-declared target, closing a direct conflict with both the user's global baseline and
  `git-repo-init`'s own scaffold-time target/Swift-version values, without weakening the defaults
  for a genuinely new, undeclared project.
- `find-skills`'s trigger narrows from "any how-do-I-question" — SPEC's own characterization,
  confirmed accurate on inspection — to explicit skill-discovery intent, with a NEGATIVE clause
  covering both exclusion classes SPEC names, reducing false-positive invocation against requests
  better served directly or by an already-installed skill.
- 24 new hermetic, offline, zero-network, static-anchor assertions extend `docs-ci.yml`'s
  `shell-tests` job from 12 to 13 entries, reusing the exact `ok`/`bad`/`PASS`/`FAIL` idiom and
  lettered-section convention every existing file in this directory already uses, so a reviewer
  already familiar with this suite needs zero ramp-up to read the new file.
- Zero new schema fields, zero new hook wiring, zero new skill, zero permission-mode change; the
  only file touched outside the five `SKILL.md` files and the new test file is one additive `PAIRS`
  line in `sync-to-claude.sh` and one appended entry in `docs-ci.yml`'s existing list.

### Negative

- The deployed `~/.claude` copies of all five skills keep today's six defects until a human runs
  `sync-to-claude.sh --apply` — the same disclosed, established "deployed stays defective until
  sync" convention as ADR-0024 through ADR-0034, repeated here rather than assumed already
  understood. For `claude-md-generator` specifically, this is the *first* time that sync path exists
  at all (Finding A); before this ADR, even a human-run sync had no `PAIRS` entry to act on for this
  file.
- `find-skills`'s body (`## When to Use This Skill`, Step 1's "Asks 'how do I do X'..." bullet) is
  now inconsistent with the newly-narrowed frontmatter trigger: the practical over-triggering defect
  is closed (the frontmatter field is what governs invocation), but a human reading the skill's own
  body after it has already been invoked sees broader usage rationale than the trigger now permits.
  Deliberately left this way (§3.6) — SPEC's cited text is line 3 only, and this is disclosed here
  rather than silently left for a future reader to puzzle over.
- `git-repo-init`'s new HITL gate is one more question a user answers before the first commit on
  every future greenfield scaffold, lengthening the wizard's happy path by one round. Mitigated,
  not eliminated: the recommended-option convention pre-selects "Approve" for a clean scaffold, and
  the wizard was arguably already non-compliant with this repository's own HITL invariant before
  this fix, not merely faster.
- Section C (`git-repo-init`) carries 7 of the new file's 24 assertions, more than any other
  section, because it resolves two SPEC-numbered findings inside one rewritten section (§3.4); a
  reviewer wanting to accept the HITL-gate fix without the browser fix, or vice versa, cannot do so
  at the file-diff granularity, only by hand-splitting the single Fase-5 hunk.
- The new test file's two positional assertions (Section C's gate-between-scaffolding-and-commit
  check, Section D's scoping-bullet-precedes-defaults check) encode the current relative ordering of
  specific text anchors, not just their presence. A future, unrelated edit that reorders
  `git-repo-init`'s Fase 5 steps or `swiftui-pro`'s Core Instructions bullets — without touching
  either defect this ADR fixes — would need to keep these two assertions in mind; none of the 12
  pre-existing hermetic test files encode ordering this way, only presence/absence and counts, so
  this is a small, new category of coupling between prose structure and test structure in this
  directory.
- `research-prompt` was checked and confirmed not to be a correct substitute for the removed
  `vibrofer-perplexity-prompt` reference (§3.3); no real skill in this repository actually covers
  Perplexity- or Vibrofer-specific research today, so a user who genuinely wants that specific
  workflow gets a plain, honest exclusion rather than a routing hint to somewhere — a strictly
  correct outcome, but a less immediately actionable one than a (nonexistent) working pointer would
  have been.

### Neutral

- No manifest schema change, no new skill, no new hook, no `settings.json` change, no
  permission-mode change anywhere in this ADR.
- Four of the five touched skills (`prompt-builder`, `git-repo-init`, `swiftui-pro`, `find-skills`)
  already carried a `PAIRS` entry before this issue (confirmed by reading `sync-to-claude.sh` before
  writing this ADR); only `claude-md-generator` needed a new one. `PAIRS` grows from 108 to 109
  entries, a single-line, additive-only change.
- `pairs-completeness.test.sh`'s self-test-then-real-check design (ADR-0024) needs no code change to
  cover the new entry; only the data addition itself is new, exercised automatically the next time
  that harness runs.
- `swiftui-pro` is a third-party-authored skill (MIT license, author Paul Hudson) vendored into this
  repository's staging tree; this ADR edits its `## Core Instructions` content exactly as SPEC
  directs, the same latitude already exercised, deploy-fidelity questions aside, for the four
  repo-native skills in this issue.
- The claude-md-generator D5 non-regression guard (ADR-0012 Task 8, `agent-notes`) was re-verified
  absent from the current file and stays absent; Finding A's edit is unrelated to, and does not
  reintroduce, that separate concern.
- This ADR neither opens nor forecloses Alt E1's "also rewrite `find-skills`'s body for full
  internal consistency" — it is explicitly left for a future issue to pick up if the residual
  inconsistency (Consequences/Negative, second bullet) is ever judged worth a dedicated fix.

---

## 5. References

- `SPEC.md` (repo root) / `docs/specs/39-skill-text-corrections-across-five-stand.spec.md` — this
  issue's spec (confirmed byte-identical)
- GitHub issue #39 — confirmed the six-item, five-file scope matches SPEC.md exactly; confirmed no
  additional per-defect audit sub-numbering is available beyond the "3.1, 3.17 to 3.21" range both
  documents already cite
- `docs/architecture/ADR-0003-concept-to-code-chain.md` — original `claude-md-generator` design,
  Branch-B `Skill`-tool invocation pattern
- `docs/architecture/ADR-0011-clean-public-repo-anonymize.md` — the "additive directive in the
  dispatch prompt, not the skill's own text" pattern this ADR's Finding A closes a gap in
- `docs/architecture/ADR-0012-agent-memory-orchestrator-mediated.md`,
  `docs/architecture/ADR-0013-native-subagent-memory-supersede-mediated.md` — D5's `claude-md-generator`
  non-regression guard, re-verified absent and not reintroduced
- `docs/architecture/ADR-0024-28-vendor-deployed-only-skills-and-hooks.md` — `staging/` +
  `sync-to-claude.sh` + `PAIRS` mechanism, `pairs-completeness.test.sh` design reused unmodified
- `docs/architecture/ADR-0025-29-refresh-stale-staging-copies.md` — §2.3/§3.2/§4-Negative, the
  explicit, named flag that this issue closes for `claude-md-generator`'s `PAIRS` gap
- `docs/architecture/ADR-0027-31-c2c-bsd-slug-autopilot-gates.md`,
  `docs/architecture/ADR-0028-32-manifest-helpers-guards.md`,
  `docs/architecture/ADR-0030-34-scope-guards.md` — structural and test-harness precedent this ADR
  reuses directly (file format), and departs from deliberately in one respect (task sequencing,
  §3.8)
- `staging/plugin/skills/concept-to-code/SKILL.md` (lines 459-479, 1796) — Branch B's dispatch
  prompt and the "additive directive" framing this ADR's Finding A now matches
- `staging/plugin/skills/project-init/SKILL.md` (lines 6, 34) — confirmed compatible, path-agnostic
  references to `claude-md-generator`, not edited
- `staging/plugin/skills/research-prompt/SKILL.md` — checked and confirmed not a correct substitute
  for the removed ghost-skill reference (§3.3)
- `docs/plugins-and-mcp-catalog.md` (line 21) — verifies `skill-creator`'s real status as a
  marketplace/catalog plugin, not a `staging/plugin/skills/` repo-native skill
- The five files this ADR patches: `staging/plugin/skills/claude-md-generator/SKILL.md`,
  `staging/plugin/skills/prompt-builder/SKILL.md`, `staging/plugin/skills/git-repo-init/SKILL.md`,
  `staging/plugin/skills/swiftui-pro/SKILL.md`, `staging/plugin/skills/find-skills/SKILL.md`
- `staging/sync-to-claude.sh`, `staging/plugin/scripts/tests/pairs-completeness.test.sh` — the one
  `PAIRS` line this ADR adds, and the harness that validates it structurally
- `.github/workflows/docs-ci.yml`, `.claude/test-cmd` — CI wiring for the new test file; the latter
  needs no edit (existing wildcard glob already covers it)
- Implementation plan: `docs/superpowers/plans/2026-07-11-39-skill-text-corrections.md`
