#!/bin/bash
# Outputs: <stack> on stdout
# swift | python | typescript | javascript | go | rust | generic
# Bash 3.2 compatible — no associative arrays, no ${v^^}
PROJECT_ROOT="${1:-.}"

if [ -f "$PROJECT_ROOT/Package.swift" ]; then
  echo "swift"; exit 0
fi
if find "$PROJECT_ROOT" -maxdepth 1 -name "*.xcodeproj" -type d 2>/dev/null | grep -q .; then
  echo "swift"; exit 0
fi
if find "$PROJECT_ROOT" -maxdepth 1 -name "*.xcworkspace" -type d 2>/dev/null | grep -q .; then
  echo "swift"; exit 0
fi
if [ -f "$PROJECT_ROOT/pyproject.toml" ] \
   || [ -f "$PROJECT_ROOT/setup.py" ] \
   || [ -f "$PROJECT_ROOT/setup.cfg" ] \
   || [ -f "$PROJECT_ROOT/requirements.txt" ] \
   || [ -f "$PROJECT_ROOT/Pipfile" ]; then
  echo "python"; exit 0
fi
if [ -f "$PROJECT_ROOT/tsconfig.json" ]; then
  echo "typescript"; exit 0
fi
if [ -f "$PROJECT_ROOT/go.mod" ]; then
  echo "go"; exit 0
fi
if [ -f "$PROJECT_ROOT/Cargo.toml" ]; then
  echo "rust"; exit 0
fi
if [ -f "$PROJECT_ROOT/package.json" ]; then
  if grep -q '"typescript"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
    echo "typescript"; exit 0
  fi
  echo "javascript"; exit 0
fi
echo "generic"
exit 0
