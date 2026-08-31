---
name: zsh-no-word-split-for-loop
description: for t in $LIST iterates once over the whole string instead of once per item, when the shell is zsh and LIST is unquoted
metadata:
  type: project
---

Bug pattern: `for t in $LIST` where `LIST` is a space-separated string
(`LIST="a b c"`) is written assuming bash/POSIX semantics: unquoted parameter
expansion word-splits on IFS, so the loop runs once per token. Under zsh
(without `SH_WORD_SPLIT`), unquoted expansion does NOT word-split by default —
`$LIST` expands to a single word, so the loop body runs exactly once with `t`
bound to the entire blob. Symptom looks like a no-op or single garbled
iteration, not a crash, which makes it easy to miss in review.

**Why:** the failure is a shell-dialect mismatch, not a typo — the script is
correct bash, wrong shell. This repo's own `~/.claude/rules/tools.md` already
documents that the Bash tool's host shell on this machine is zsh
(`#zsh-word-split`), so any script written assuming bash and run through that
tool hits this silently.

**Fix (root cause, not suppression):** don't rely on implicit splitting.
Either build a real array from the start —
`list=(a b c); for t in "${list[@]}"; do ...; done` — or, when the input truly
arrives as a delimited string, split explicitly and portably:
`while IFS= read -r t; do ...; done < <(printf '%s\n' $LIST)` won't fix it
either without care; the reliable cross-shell form is
`arr=(); while IFS= read -r x; do arr+=("$x"); done < <(cmd)` (already the
project convention for bash 3.2 arrays, see `#bash-32`), or wrap the loop in
`bash <<'EOF' ... EOF` if bash's own splitting semantics are required.

**How to apply:** whenever debugging a loop that silently runs once (or
processes the whole list as one item) on this machine, check whether the shell
executing it is zsh before looking for a bash bug. This is a single-probe
diagnosis: `echo $ZSH_VERSION` in the failing context, or check whether the
script was invoked via the Bash tool (host is zsh) vs a `#!/bin/bash` script
executed directly (real bash, splits normally). See also
`~/.claude/rules/tools.md` `#zsh-word-split`.
