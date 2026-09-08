#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
candidate="${1:-working-tree}"
result="$HOME/Library/Application Support/DeskMux/latest-motion-research.json"
failure="$HOME/Library/Application Support/DeskMux/latest-motion-research-failure.json"

started_at="$(date +%s)"
cd "$project_root"
swift run deskmux-agent research trigger --candidate "$candidate" >/dev/null

for _ in {1..120}; do
  if [[ -f "$result" ]] && [[ "$(stat -f %m "$result")" -ge "$started_at" ]] \
    && [[ "$(jq -r '.candidate // empty' "$result")" == "$candidate" ]]; then
    jq '{candidate, appBuild, traceSampleCount, assessment}' "$result"
    exit 0
  fi
  if [[ -f "$failure" ]] && [[ "$(stat -f %m "$failure")" -ge "$started_at" ]] \
    && [[ "$(jq -r '.candidate // empty' "$failure")" == "$candidate" ]]; then
    jq '{candidate, appBuild, failure}' "$failure" >&2
    exit 1
  fi
  sleep 1
done

print -u2 -- "Timed out waiting for DeskMux motion experiment '$candidate'."
exit 1
