# SPEC — the dirty-classify fence reads porcelain v1 so a renamed artifact classifies as OTHER

Source: GitHub issue #297

## Objectives

1. Make a renamed chain artifact classify as a chain artifact rather than as `OTHER`.
2. Make a path containing a space classify correctly.
3. Keep the manifest exemption applying to exactly one file and no other, and keep the fence's
   exit-3 "did not run" branch.

## Scope

In: the declared fence `c2c-step5-preflight-dirty-classify` in Step 5.0.1 of
`concept-to-code/SKILL.md` — how it reads `git status` output, how it shortens a path against the
repository root, and how it classifies each dirty entry as a chain artifact, the exempt manifest, or
`OTHER`. Reproducing both failure cases against the fence before designing, and checking what the
existing fixtures actually cover, given ADR-0089's record that path normalisation is only
half-evidenced.

Out: the exemption decision itself — ADR-0089 settled that the manifest and only the manifest leaves
the dirty set, bounded by `manifest-validate.sh` rather than by trust. The other Step 5 pre-flight
assertions. The recovery-baseline check (#244, ADR-0103).

## Stack

Bash 3.2 (macOS-portable) shell scripts under `staging/plugin/scripts/` and
`staging/plugin/skills/*/scripts/`; Markdown SKILL.md instruction files; awk predicates; a 68-file
`*.test.sh` harness under `staging/plugin/scripts/tests/` run by `.claude/test-cmd`; GitHub Actions
CI (`ci`, `markdownlint`, `links`). No application runtime.

## Architecture

- `staging/plugin/skills/concept-to-code/SKILL.md` — Step 5.0.1, the fence declared
  `<!-- fence-contract: c2c-step5-preflight-dirty-classify -->`. It runs `git status --porcelain`,
  strips the status columns, filters out the manifest, resolves the repository root and shortens
  each path against it, then classifies into `CHAIN` and `OTHER` and emits one of the
  `PREFLIGHT_*` tokens. The block immediately below it interprets each token; the block below that
  states the known limits this issue closes. Line numbers will have moved; resolve by reading.
- `staging/plugin/skills/concept-to-code/scripts/manifest-validate.sh` — the bound on the exemption:
  what is exempt is the manifest's dirtiness, never its content.
- `staging/plugin/scripts/tests/recovery-preflight.test.sh` — the harness file that extracts and
  executes this fence, holding ADR-0089's eleven fixtures; where the new assertions belong and where
  the half-evidenced normalisation is visible.
- `staging/plugin/scripts/tests/fence-contract-coverage.test.sh` — enforces that a declared fence is
  executed by a test and parses under `bash -n`; any rewrite must keep both true.
- `staging/plugin/scripts/tests/plant-check.sh` — the plant registry runner (ADR-0108).
- `docs/architecture/ADR-0089-239-step5-preflight-manifest-exemption.md` — the source, whose quoted
  line number will have moved, and which records the `.gitignore`-dependent `*.bak` behaviour that
  two unrelated checks rely on.

## Data model

Each dirty entry, as classified by the fence:

- `CHAIN` — a planning artifact the chain itself produced (`SPEC.md`, the ADR, the plan,
  `CLAUDE.md`).
- the exempt manifest — filtered out before classification, exactly one file.
- `OTHER` — work of unknown provenance, the ADR-0050 §D2 case.

Emitted tokens: `PREFLIGHT_BOTH`, `PREFLIGHT_OTHER`, the clean/chain-only cases, and exit 3 for
"did not run".

## API / Interfaces

The fence is executed by the harness by its `fence-contract:` id and by the orchestrator at Step 5
entry. Its interface is its stdout token plus its exit status; the caller branches on the token.
`git status --porcelain` (v1) is the input format at issue — porcelain v2 or `-z` are the candidate
alternatives, each with its own parsing consequences.

## UI flows

None.

## Edge cases

- A renamed chain artifact: porcelain v1 emits `old -> new`, which the current classifier reads as
  a single unmatched path and calls `OTHER`.
- A path containing a space: porcelain v1 quotes it, so the literal comparison fails.
- A path containing a quote or a non-ASCII byte, which porcelain v1 also escapes — the same class as
  the space, and worth reproducing rather than assuming.
- A rename where only one side is a chain artifact.
- The manifest itself renamed, which must not silently widen the exemption (R-03).
- Path normalisation: the chain's manifest path is whatever `$PWD` was at Gate 0, while
  `git rev-parse --show-toplevel` returns a physical path; on macOS `/tmp` is a symlink to
  `/private/tmp` and a checkout is reachable through two differently-cased paths. ADR-0089 records
  that reverting one half of the normalisation fires no assertion.
- `*.bak` debris from `sed -i.bak` at Step 5.0.3 is gitignored, and that is load-bearing for this
  assertion and for the merge-back escape check — a `.gitignore` edit must not break either
  silently.
- Per the standing rules in the issue footer, the fence is a checker: exit 3 must stay distinct from
  a clean tree, or an unrunnable classifier is indistinguishable from success.

## Success criteria

- [ ] R-01 — a renamed chain artifact classifies as a chain artifact.
- [ ] R-02 — a path containing a space classifies correctly.
- [ ] R-03 — the manifest exemption still applies to exactly one file and no other, and the fence
      keeps its exit-3 "did not run" branch.
