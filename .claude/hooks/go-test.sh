#!/usr/bin/env bash
# PostToolUse hook (Edit|Write): run `go test` for the package containing the
# edited .go file. Failures exit 2 so the output is fed back to Claude.
set -uo pipefail

input=$(cat)
file=$(jq -r '.tool_input.file_path // empty' <<<"$input")

[[ "$file" == *.go ]] || exit 0

root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$root" || exit 0

# Only test files that live inside this module.
case "$file" in
  "$root"/*) rel="${file#"$root"/}" ;;
  /*) exit 0 ;;
  *) rel="$file" ;;
esac

pkg_dir=$(dirname "$rel")
[[ -d "$pkg_dir" ]] || exit 0

if ! output=$(go test "./$pkg_dir" 2>&1); then
  {
    echo "go test ./$pkg_dir failed after editing $rel:"
    echo "$output"
  } >&2
  exit 2
fi

echo "go test ./$pkg_dir passed"
exit 0
