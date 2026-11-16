#!/usr/bin/env bash
# PostToolUse hook: run `go mod tidy` only when dependencies may have changed.
#
# Triggers:
#   - Edit/Write to go.mod
#   - Edit/Write to a .go file where the change touches an import
#     (an `import` keyword or a quoted import path line)
#   - Bash commands that run `go get`
#
# Ordinary .go edits that don't touch imports are skipped, keeping edits fast.
set -uo pipefail

input=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$input")

should_tidy=false

case "$tool" in
  Edit|Write)
    file=$(jq -r '.tool_input.file_path // empty' <<<"$input")
    case "$file" in
      */go.mod|go.mod)
        should_tidy=true
        ;;
      *.go)
        # Text that changed: Edit -> old/new strings, Write -> full content.
        changed=$(jq -r '[.tool_input.old_string, .tool_input.new_string, .tool_input.content]
                         | map(select(. != null)) | join("\n")' <<<"$input")
        # `import "x"`, `import (`, or a line inside an import block such as
        # `"net/http"` / `alias "github.com/x/y"`.
        if grep -Eq '(^|[[:space:]])import[[:space:]]*[("]|^[[:space:]]*([A-Za-z_.][A-Za-z0-9_]*[[:space:]]+)?"[^"[:space:]]+"[[:space:]]*$' <<<"$changed"; then
          should_tidy=true
        fi
        ;;
    esac
    ;;
  Bash)
    cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
    if grep -Eq '(^|[;&|[:space:]])go[[:space:]]+get([[:space:]]|$)' <<<"$cmd"; then
      should_tidy=true
    fi
    ;;
esac

$should_tidy || exit 0

root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$root" || exit 0
[[ -f go.mod ]] || exit 0

before=$(cat go.mod go.sum 2>/dev/null | shasum)

if ! output=$(go mod tidy 2>&1); then
  {
    echo "go mod tidy failed:"
    echo "$output"
  } >&2
  exit 2
fi

after=$(cat go.mod go.sum 2>/dev/null | shasum)
if [[ "$before" != "$after" ]]; then
  echo "go mod tidy updated go.mod/go.sum"
fi
exit 0
