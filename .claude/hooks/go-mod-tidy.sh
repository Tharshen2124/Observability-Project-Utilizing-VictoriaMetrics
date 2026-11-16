#!/usr/bin/env bash
# Stop hook: run `go mod tidy` once at the end of Claude's turn, only when needed.
#
# Running on Stop (instead of PostToolUse) means it never overlaps with the
# per-edit `go test` hook, and it covers every way dependencies can change
# (edited imports, edited go.mod, `go get` via Bash) in a single pass.
#
#   1. Skip unless Go files / go.mod / go.sum have uncommitted changes.
#   2. Ask `go mod tidy -diff` whether tidy would change anything.
#   3. Only then run `go mod tidy`.
#
# If tidy fails, exit 2 so Claude keeps going and fixes it (once; a second
# failure in the same stop cycle is reported without blocking again).
set -uo pipefail

input=$(cat)
stop_hook_active=$(jq -r '.stop_hook_active // false' <<<"$input")

root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$root" || exit 0
[[ -f go.mod ]] || exit 0

# Nothing Go-related changed this session -> nothing to tidy.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  [[ -n "$(git status --porcelain -- '*.go' go.mod go.sum 2>/dev/null)" ]] || exit 0
fi

# Exit 0 = already tidy. Anything else = needs tidy (or errored; tidy will tell us).
go mod tidy -diff >/dev/null 2>&1 && exit 0

if ! output=$(go mod tidy 2>&1); then
  msg="go mod tidy failed:
$output"
  if [[ "$stop_hook_active" == "true" ]]; then
    jq -n --arg m "$msg" '{systemMessage: $m}'
    exit 0
  fi
  echo "$msg" >&2
  exit 2
fi

jq -n '{systemMessage: "go mod tidy updated go.mod/go.sum"}'
exit 0
