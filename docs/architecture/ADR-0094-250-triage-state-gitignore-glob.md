# ADR-0094 — RTF gitignored its state file by branch name, one dead line at a time

- **Status:** Accepted
- **Date:** 2026-07-31
- **Issues:** #250 (found by the Phase 7.1 shakedown run, at Step 7, while inspecting what Step 7
  had left to commit)
- **Related:** ADR-0039 (both directions per contract), ADR-0043 (a check that did not run is not a
  check that found nothing), `commit/SKILL.md` (the `git check-ignore` exit-code contract, already
  written there)

## Context

`review-triage-fix`'s state file is per-branch by design — a shared file produces false
"resolved"/"oscillates" verdicts when a previous cycle ran on a different branch. Step 5's
`triage-state.sh commit` then gitignored it by appending its **resolved** name:

```diff
+.claude/.triage-fix-last-feat_222-vendor-deployed-only-skills.json
```

The branch is deleted at merge. The `.gitignore` line is not. One dead entry per branch, forever,
and on a public repo that is a list of every feature branch ever reviewed, abandoned ones included.

**It also defeated its own purpose.** A per-branch line protects exactly one branch; the *next*
branch is unprotected until its own cycle appends its own line. The mechanism that exists to keep
RTF state out of the repository was, on any new branch, not yet doing it.

## Decision

### D1 — Append a glob, not the resolved name

`${pref}.triage-fix-last-*.json`. One entry, permanent, covering every branch including the first
cycle on a new one, and it never grows.

### D2 — Ask `git check-ignore`, not a literal grep for the script's own line

A human may already have written a broader rule by hand, and **this repository's own `.gitignore` is
the proof**: it carried `.claude/.triage-fix-last*.json` before the glob existed. A literal grep
recognises only the one line this script writes and would append a duplicate beside any broader
rule.

Its exit-code contract is the one `commit/SKILL.md` already documents: **1 means "not ignored" and
is a clean result, not a failure**; only 128 is an error. Anything non-zero takes the append branch,
which is the safe direction — the append is idempotent, so the worst case is a no-op.

The literal grep is kept as a fallback beneath it, for the case where `check-ignore` itself cannot
run.

### D3 — Pass a basename, because `git -C` moves the cwd

`d` is the state file's own directory. `git -C "$d" check-ignore -- "$SF"` resolves a *relative*
`$SF` against `$d` a second time, producing `.claude/.claude/…` — a path no rule matches, so the
check reports "not ignored" for a file that is ignored.

RTF itself passes an **absolute** path, so this is defensive rather than load-bearing today. It is
pinned anyway: *defensive* and *untested* together are what make a later simplification look free.

## Verification

18 assertions in the new `triage-state-gitignore.test.sh`, registered in both CI registries.

`T1b` is the red evidence and it is **derived**: the pre-#250 append is reconstructed from the
shipped script by `sed`, so it cannot drift into testing some other logic. Three branches must still
produce three dead lines under it.

| plant | fires |
|---|---|
| the glob reverted to the resolved name | **T2, T3, T4** |
| `check-ignore` removed | T5, T6, T7 |
| the basename reverted (the `git -C` bug) | T1a, **T10b** |
| the docs-ci registration removed | T13 |

## The assertion that took three tries, which is the part worth keeping

`T10b` exists to pin D3. Its first two drafts **passed and caught nothing**, and the reason is
specific enough to reuse:

1. **Seeded with the script's own glob** — the literal-grep fallback suppressed the append on its
   own, so the `check-ignore` branch was never exercised.
2. **Seeded with `.claude/`** — that rule ignores the whole directory, so it also covers the
   *doubled* path `.claude/.claude/…` the bug produces. `check-ignore` answered "ignored" for the
   wrong reason and the assertion passed anyway.

The seed had to satisfy two conditions at once: differ from the script's own glob, **and** not cover
the doubled path. `.claude/.triage-fix-last*.json` does both, verified by running `check-ignore`
against both paths before writing the assertion.

Neither draft was detectably wrong by reading. Both were caught by requiring the plant to fire —
**an assertion that cannot be made to fail is pinning nothing**, and the corollary is that a fixture
must be chosen against the failure mode, not merely be plausible.

Full harness 55/55.

## Consequences

- A repository that already has per-branch dead lines keeps them; this stops the growth and does not
  sweep. This repository has none (`T12` asserts it live, against the real file).
- The glob is `.triage-fix-last-*.json`, with the dash. A hypothetical state file named
  `.triage-fix-lastX.json` would not be covered — the broader `.claude/.triage-fix-last*.json` in
  this repository's own `.gitignore` is not what the script writes, and the two differ by that dash.
- `.gitignore` is still appended to by a script, silently. Unchanged from before, and out of scope.
