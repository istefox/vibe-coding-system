# CI wiring and shell portability

## CI wiring
- `.github/workflows/docs-ci.yml`'s `shell-tests` job uses an explicit **named list**, not a glob.
  `.claude/test-cmd` globs `staging/plugin/scripts/tests/*.test.sh` and auto-picks up new files;
  CI does not. A brand-new `*.test.sh` file needs a manual append to the yml list — always a plan
  task, never a footnote (four prior instances of this exact gap, ADR-0113).
- Extending an **existing** `*.test.sh` file needs no registry edit — both the glob and the named
  list already cover it. Only a new file needs the append.
- The named list uses bare harness names without the `.test.sh` suffix — grep with the bare name.
- `staging/plugin/skills/*/tests/*` (each skill's own integration harness) and any file matching
  `<name>-check.sh` one level below `plugin/scripts/` (not `*.test.sh`) are deliberately outside
  both `docs-ci.yml` and `.claude/test-cmd` — `$HOME`-coupled by design or exempt from PAIRS.
- `pairs-completeness.test.sh` runs `check_complete` on **five** populations, re-derived 2026-09-06:
  `plugin/agents/*.md`, `user/rules/*.md`, `plugin/skills/*/SKILL.md`,
  `plugin/skills/*/references/*.md`, and `plugin/scripts/*.sh` (this last one with a five-entry
  exemption file for probe-only tooling). **A new `plugin/scripts/*.sh` DOES need a PAIRS entry** —
  an earlier version of this line said the opposite and was wrong. `check_exemptions_live` also
  asserts each exemption still has a subject, so an exemption cannot outlive its file.
- `docs/architecture/**` IS linted (`markdownlint-cli2`, `default: false` + 14 rules) —
  `docs/superpowers/**` is NOT (ignore list + links-job exclude), so a plan file is unlinted but an
  ADR is not. Run `npx markdownlint-cli2 <adr>` before returning: MD018 (line starting `#<digits>`)
  and MD038 (code span with leading/trailing space) are the two that catch ADR prose in practice.
- **My own memory store is CI-checked repo content, not a scratch area** (verified 2026-08-31).
  `.claude/agent-memory/**` is neither gitignored nor in `.markdownlint-cli2.jsonc`'s `ignores`
  (only `node_modules`, `docs/superpowers`, `staging/plugin/skills`, `staging/plugin/agents`), so
  these files sit inside the default lint population (314 files, `Finding: **/*.md !…`) AND inside
  the **blocking** offline lychee job (`--offline --include-fragments '**/*.md'`, excluding only
  `docs/superpowers`). The sibling `.claude/agent-memory-local/` IS gitignored — the committed vs
  machine-local split is the `memory:` scope, not a naming accident.
  Consequences when editing memory: a `MEMORY.md` index line of the form `- [T](topics/x.md)`
  pointing at a file not yet written turns a blocking CI job red, so the "link liberally, a
  dangling link is fine" guidance in my own agent prompt holds only for `[[wikilink]]` syntax
  (invisible to both checkers), never for the markdown-link index form. Anchors are checked too
  (`--include-fragments`). Net: of my three write roots, two (`docs/architecture/**`,
  `.claude/agent-memory/architect/**`) are lint- and link-gated and one
  (`docs/superpowers/plans/**`) is gated by neither.

## Shell / bash portability
- Host shell on this machine is zsh 5.9 and does **not** word-split unquoted expansions. Anything
  written into a `SKILL.md` bash fence is tested under bash by the harness, which cannot observe
  this class of divergence at all: `cmd $VAR`, `for x in $VAR`, `${v:+a "$b"}`, unmatched globs
  (`nomatch`), `echo` backslash escapes.
- `bash -n` does not parse a heredoc body — a check asserting "a fence parses" goes vacuous the
  moment that fence's body moves inside a heredoc.
- Bash `case` pattern matching (not pathname expansion) treats `*` as matching across `/` —
  portable to bash 3.2, safe for glob-style string matching without a regex engine.
- A glob pattern held in a variable and used unquoted as a `case` pattern does NOT re-expand —
  matched as literal text (verified bash 3.2.57). `${p#"$ROOT"/}` (quoted inner expansion) strips a
  prefix literally even when `ROOT` contains a glob metacharacter.
- `~/.claude/rules/shell.md`'s global default (`set -euo pipefail`) conflicts with this project's
  dominant convention (`set -u` only) — follow the project precedent, flag rather than override.
- Files under `staging/` are stored non-executable (mode 644): run as `bash <path>`, never
  `./<path>` — a direct invocation exits 126 and reads as a structural error in a sweep.
