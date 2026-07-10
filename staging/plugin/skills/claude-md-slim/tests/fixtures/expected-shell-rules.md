---
paths:
  - "**/*.{sh,bash}"
---

## Shell Conventions

Shell scripts in this project run on bash for portability and zsh for interactive sessions.
Executable scripts live under scripts/ with the .sh extension.
The shebang line is `#!/bin/bash` on every script.
For macOS automation rely on AppleScript via osascript when needed.
Run shellcheck on each new script added to the tree.
