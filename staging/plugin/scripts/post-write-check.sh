#!/usr/bin/env bash
# ADR-0039 D1-D4: post-write-check.sh — PostToolUse hook on Edit|Write, bash 3.2-clean.
#
# Runs a fast, file-scoped correctness check on the file just written and reports errors back
# to the model. Zero LLM tokens. Sibling of auto-format.sh, and ordered after it in
# settings.json so formatting noise is gone before this looks at the file.
#
# Contract:
#   - ADVISORY, NEVER BLOCKING (D2). Always exits 0. Never emits `decision`, which is what
#     separates advisory from blocking. Mid-implementation code is legitimately incomplete;
#     blocking on it would stall a coder on code it was about to finish.
#   - ONE FILE, NEVER THE PROJECT (D3). No project-wide type check: too slow per write, and
#     mostly noise about symbols that do not exist yet on a half-finished tree.
#   - ERROR SEVERITY ONLY (D4). Warnings and style suggestions are dropped. The value of this
#     hook is that everything it says is true.
#   - Best-effort: a missing engine is skipped in silence, never reported as a failure.
#
# Output channel — the one part that is not obvious:
#   PostToolUse stdout on exit 0 goes to the debug log, NOT into context. Only UserPromptSubmit,
#   UserPromptExpansion and SessionStart add stdout to context (code.claude.com/docs/en/hooks).
#   The model sees a PostToolUse hook only through hookSpecificOutput.additionalContext. Getting
#   this wrong is what made post-md-tells-hint.sh a no-op for its entire life (ADR-0040).
#
#   Unlike prompt-en-prose-detect.sh, this script emits ONLY the nested envelope. That script
#   emits a dual form for UserPromptSubmit for a historical reason (ADR-0034 D4); for PostToolUse
#   the nested form is the only documented shape, so there is nothing to hedge against.

set -u

INPUT=$(cat 2>/dev/null) || INPUT=""
[ -z "$INPUT" ] && exit 0

FILE_PATH=$(printf '%s' "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('file_path', ''))
except Exception:
    print('')
" 2>/dev/null || true)

[ -z "$FILE_PATH" ] && exit 0
[ -f "$FILE_PATH" ] || exit 0   # written then deleted, or never landed on disk

ERR=""

# capture <label> <command...> — run a check, keep its output only if it fails.
capture() {
  _label="$1"; shift
  _out=$("$@" 2>&1)
  if [ "$?" -ne 0 ]; then
    [ -n "$ERR" ] && ERR="$ERR
"
    ERR="$ERR[$_label]
$_out"
  fi
}

case "$FILE_PATH" in
  *.sh|*.bash)
    capture "bash -n" bash -n "$FILE_PATH"
    command -v shellcheck >/dev/null 2>&1 && capture "shellcheck" shellcheck -S error "$FILE_PATH"
    ;;
  *.py)
    # cfile=/dev/null on purpose: `python3 -m py_compile` would write __pycache__ into the
    # project tree. A check must not leave anything behind.
    capture "py_compile" python3 -c \
      "import py_compile,sys; py_compile.compile(sys.argv[1], cfile='/dev/null', doraise=True)" \
      "$FILE_PATH"
    command -v ruff >/dev/null 2>&1 && capture "ruff" ruff check --quiet "$FILE_PATH"
    ;;
  *.json)
    if command -v jq >/dev/null 2>&1; then
      capture "jq" jq empty "$FILE_PATH"
    else
      capture "json" python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$FILE_PATH"
    fi
    ;;
  *.yml|*.yaml)
    capture "yaml" python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$FILE_PATH"
    ;;
  *.swift)
    # swiftc -parse is a syntax check and nothing more. swiftlint is deliberately NOT used
    # here: it reports style rules (identifier_name, line_length) at severity `error`, so on
    # `let x = 1` it complains the name is too short. That is the noise D4 exists to keep out.
    # Style belongs to auto-format and to the reviewer, not to a per-write correctness check.
    command -v swiftc >/dev/null 2>&1 && capture "swiftc -parse" swiftc -parse "$FILE_PATH"
    ;;
  *.ts|*.tsx|*.js|*.jsx)
    # Only with a project-local eslint. --no-install keeps npx from downloading anything.
    # package.json is looked for upward from the file, not in $PWD: the hook's working
    # directory is the session's, which need not be the edited file's project.
    _d=$(dirname "$FILE_PATH"); _i=0; _pkg=""
    while [ -n "$_d" ] && [ "$_i" -lt 20 ]; do
      [ -f "$_d/package.json" ] && { _pkg="$_d"; break; }
      [ "$_d" = "/" ] && break
      _d=$(dirname "$_d"); _i=$((_i + 1))
    done
    if [ -n "$_pkg" ] && command -v npx >/dev/null 2>&1; then
      capture "eslint" npx --no-install eslint --quiet "$FILE_PATH"
    fi
    ;;
  *)
    exit 0
    ;;
esac

[ -z "$ERR" ] && exit 0

FILE_PATH="$FILE_PATH" ERR="$ERR" python3 -c "
import json, os
ctx = 'post-write check failed on %s:\n\n%s\n\nFix it in the next edit if it is a real defect. This check is advisory and never blocks.' % (
    os.environ['FILE_PATH'], os.environ['ERR'])
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'PostToolUse',
        'additionalContext': ctx
    }
}))
" 2>/dev/null || true

exit 0
