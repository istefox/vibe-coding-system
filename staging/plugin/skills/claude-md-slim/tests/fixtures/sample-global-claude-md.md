# Global CLAUDE.md (fixture)

This fixture stands in for ~/.claude/CLAUDE.md in --global duplication tests.

## Shell Conventions

Shell scripts in this project run on bash for portability and zsh for interactive sessions.
Executable scripts live under scripts/ with the .sh extension.
The shebang line is `#!/bin/bash` on every script.
For macOS automation rely on AppleScript via osascript when needed.
Run shellcheck on each new script added to the tree.

## Identity

Respond in English by default. Tone is direct and technical with no filler phrasing.
Confidence levels declared in chat, never embedded in deliverable files.
