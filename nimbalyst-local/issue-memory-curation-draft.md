TITLE: Step 5 memory shard curation never produced `.claude/agent-memory/coder/MEMORY.md`

BODY:

## What was measured

Scan of this repo's own Claude Code transcripts (last 60 days, CC 2.1.259), 69 coder dispatches
identified by the `PATTERN:` text or the `TEST-AUTHORING SCOPE` brief marker (lower bound, the
records carry no agent-type field):

| signal | value |
|---|---|
| coder memory shards written under `.claude/agent-memory/coder/topics/` | 2 |
| `MEMORY.md` indexes curated by the orchestrator | 0 |
| runs where a coder read a shard back by hand | 3 |

## Where the gap is

`staging/plugin/skills/concept-to-code/references/step5-implementation.md`, sub-step 7b and the
"Memory shard curation (VCS-057, ADR-0184)" block: the orchestrator is instructed to curate the
coder's shards into `MEMORY.md` once, after the last merge-back. Nothing verifies the block ran,
and in practice it never did. The producer (coder shard writes, enforced by
`coder-memory-scope.sh`) has no consumer on the orchestrator side (rule 17).

## What ADR-0192 did and did not do

ADR-0192 closed the coder-side half: Process step 1 now lists `topics/` and reads the shards
whose name matches the task. The orchestrator-side curation is untouched; this issue is that
half.

## Suggested shape (not decided)

- A check at the Step 5 → 6 boundary: if `topics/` gained a file during this Step 5 and
  `MEMORY.md` was not touched, report it (reporter idiom, `CLEAN` when nothing to say).
- Or drop the curation sub-step and let the coder's read-by-name in Process step 1 be the only
  consumer, recording that decision in an ADR.

Either way, measure first (rule 13): re-run the transcript scan after 30 or more dispatches with
the ADR-0192 coder and see whether read-by-name makes the index redundant.

Refs: ADR-0184, ADR-0192, `coder-discipline.test.sh` CD3.
