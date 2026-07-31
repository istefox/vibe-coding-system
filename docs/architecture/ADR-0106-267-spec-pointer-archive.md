# ADR-0106 — A pointer at a slot, and a SPEC that was archived only if someone else displaced it

- **Status:** Accepted
- **Date:** 2026-07-31
- **Issues:** #267 (measured while fixing #228, filed rather than bundled)
- **Related:** ADR-0096 (#228, archive-on-displacement), ADR-0075 (do not rewrite historical
  records), ADR-0071 §D2 (`--include`, and why it is needed here), ADR-0104 (#249, the collapse
  this must run after)

## Context

All 41 manifests record `artifacts.spec: <project-root>/SPEC.md`, and root `SPEC.md` is a single
mutable slot every chain overwrites. The pointer therefore resolves, for every one of them, to
whatever the slot holds today — **right for at most one manifest, and that one by coincidence.**

### The second gap, which #267 does not name

ADR-0096 archives the **outgoing** SPEC when a new chain is about to overwrite the slot:
archive-on-**displacement**. So a chain's SPEC is archived only if a **later** chain happens to
displace it. **The most recent chain's SPEC is never archived.**

This repository is the proof. #176's SPEC was archived by hand by issue #229; #222's was archived by
hand today, while fixing #228; and `120-accessibility-i18n` still has no archive under its slug.
36 archives for 41 manifests.

## Decision

### D1 — Step 7.0b: archive-on-completion, the other trigger

After the ADR-0104 collapse and before invoking `commit`, the chain archives its **own** SPEC and
repoints the manifest at the result.

**The two triggers compose rather than duplicate**, and that is a property of `spec-archive.sh`
rather than of the ordering: it compares by **content**, so a second call on the same SPEC reports
`ALREADY` and writes nothing (`SP6d` executes exactly that).

### D2 — On failure the pointer is left alone

`NOSPEC`, `COLLISION`, or exit 3 → say which and change nothing. **A pointer at a slot is today's
behaviour; a pointer at an archive that was never written is a new defect.** The failure direction
matters more than the success here.

### D3 — Historical manifests are not rewritten

ADR-0075 declined exactly this for the five dead `project_root` paths: falsifying a record for no
consumer is worse than leaving it accurate-for-its-moment. Nothing reads `artifacts.spec` on a
terminal manifest. `SP5` is the forward guard — the corpus keeps its 41 slot pointers.

### D4 — Both new paths are passed to `commit` with `--include`

Found while writing the block, not afterwards. **The ADR-0104 collapse leaves everything staged**,
and `commit`'s Step 1 then takes the staged set only — so the freshly-written archive (untracked)
and the freshly-repointed manifest (tracked, modified *after* staging) would **both** be silently
excluded from the commit.

`--include` exists for precisely this caller shape (ADR-0071 §D2), and Gate 4.0 already uses it the
same way.

## Verification

11 assertions in `spec-pointer-archive.test.sh`, plus a `Z1` floor. Harness 67/67.

Seen RED: **4 of 11** — `SP1`, `SP2`, `SP3`, `SP4`, the wiring. `SP6`, `SP6b`, `SP6c`, `SP6d` passed
**before** the wiring existed, deliberately: they prove the helpers can do this independently of
whether anything calls them, so a failure there means the mechanism broke rather than the wiring.
`SP0` and `SP5` are the derived premise and the do-not-rewrite guard.

Four planted defects, all fired: the archive call removed (`SP1`), the repoint removed (`SP2`), the
two triggers no longer distinguished (`SP3`), the failure branch removed (`SP4`).

**`SP1`'s first form matched the prose.** It was `grep -q 'spec-archive.sh'`, and Step 7
legitimately names the script while explaining how the two triggers compose — so the plant that
deleted the actual invocation walked straight through. It now requires the invocation line.
**Rule 12, fifth instance in one day**, after `spec-archive.test.sh` `SA10`,
`gate0-recommendation.test.sh` `N9`, and `gate5-state-removal.test.sh` `GR1`/`GR5`.

## Consequences

- **Every completed chain now writes one more file** — its own SPEC into `docs/specs/` — and commits
  it. On a chain whose SPEC was already displaced and archived, it is a no-op.
- **`artifacts.spec` now means two different things depending on when the manifest was written.**
  Historical ones name a slot; new ones name an archive. Documented rather than reconciled, because
  reconciling means rewriting 41 records ADR-0075 says to leave alone.
- The repoint happens after everything that reads `artifacts.spec` during the chain, so nothing
  in-flight sees the change. That ordering is load-bearing and unasserted.
- Inert until sync.
