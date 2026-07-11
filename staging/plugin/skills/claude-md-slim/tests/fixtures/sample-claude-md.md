# Sample Project CLAUDE.md

This file documents the project conventions for a fictional codebase used in skill tests.
It exists only as a fixture and is not loaded outside the harness.

## Shell Conventions

Shell scripts in this project run on bash for portability and zsh for interactive sessions.
Executable scripts live under scripts/ with the .sh extension.
The shebang line is `#!/bin/bash` on every script.
For macOS automation rely on AppleScript via osascript when needed.
Run shellcheck on each new script added to the tree.

## Python Environment

Use python3 for interpreters; the venv lives at .venv in the repo root.
Install dependencies via pip from requirements.txt with pinned versions.
Run scripts as `python3 path/to/file.py` from the activated venv.
Format code with black and lint with ruff before submitting changes.
The Python interpreter version is recorded in .python-version.

## Git Workflow

Use Conventional Commits in English with types feat, fix, refactor, docs, test, chore, perf.
Always work on a feature branch; never commit directly to main.
Rebase your branch onto main before opening a pull request.
The repository follows a trunk based workflow with short lived branches.
Squash and merge is the default integration strategy.

## Swift and Xcode

Swift 6 with strict concurrency; use SwiftUI for views and SwiftData for persistence.
Build via xcodebuild from the terminal: `xcodebuild test -scheme MyScheme`.
Source files use the .swift extension and follow Apple naming guidelines.
Always run xcodebuild test before declaring a feature done.
The AppKit layer is used only for macOS-specific UI features.
