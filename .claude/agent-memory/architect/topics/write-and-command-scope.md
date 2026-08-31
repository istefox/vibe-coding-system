# architect's write scope and command scope

- Write scope is now three roots (VCS-056): `docs/architecture/**`, `docs/superpowers/plans/**`,
  and `.claude/agent-memory/architect/**` (this memory dir), enforced by `test-write-scope.sh`.
  Nothing else — not even the session scratchpad. Do verification work with `bash <<'EOF'`
  heredocs writing into `mktemp -d`, never with a Write to a temp file outside these three roots.
- `Bash` grant is read-only git only (`git log/diff/show/status/rev-parse`); `git commit/push/add`
  and every mutating subcommand are blocked by `agent-command-scope.sh` even wrapped in a Bash
  heredoc or a `python3 -c` — it pattern-matches the full command string, including inert heredoc
  *content*. `gh issue list`/`gh issue view` are not git verbs and do work.
- `git init` is blocked even inside written-out heredoc text meant for a future script, not a
  command actually being run. A differential simulation needing a scratch repo cannot be run at
  design time — hand it to the coder as a declared plant, or rely on documented tool semantics
  (`git help gitignore`) and existing passing assertions as proxies.
- `permissionMode: plan` (SDK-level, not this repo's own gate) blocks every Write/Edit pending
  manual approval regardless of allow rules — any agent whose deliverable is unattended writes
  cannot carry this field.
- `effort: max` does not persist in file-based agent frontmatter (session-only); use `xhigh`.
- Tool-permission path-pattern matching is documented for Read/Grep/Edit only, **not Write** — no
  frontmatter syntax scopes Write to a path glob on its own; enforcement needs a hook
  (`test-write-scope.sh`'s pattern) or the boundary stays prose-only.
- `memory: project` (VCS-056) auto-grants Write/Edit with **no path restriction at the tool-schema
  level** — same shape as every other unscoped grant above. The hook is what makes the boundary
  real, not the frontmatter field.
