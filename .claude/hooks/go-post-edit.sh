#!/usr/bin/env bash
# PostToolUse hook (Edit|Write): run the Go hooks in sequence.
#
# Claude Code runs all hooks matching the same event in parallel, so instead
# of registering go-mod-tidy.sh and go-test.sh separately, this wrapper runs
# them one after another on the same input:
#
#   1. go-mod-tidy.sh  (only tidies if go.mod or imports changed)
#   2. go-test.sh      (tests the edited file's package)
#
# If tidy fails, tests are skipped since they would fail for the same reason.
set -uo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
input=$(cat)

"$dir/go-mod-tidy.sh" <<<"$input"
status=$?
[[ $status -eq 0 ]] || exit "$status"

"$dir/go-test.sh" <<<"$input"
