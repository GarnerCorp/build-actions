#!/usr/bin/env bash

set -e

summary_label="$1"

if [ -n "${CRANE_REGISTRY:-}" ] && [[ "$source" != "$CRANE_REGISTRY/"* ]]; then
  local_image="$CRANE_REGISTRY/copy-image:${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}-${RANDOM}"
  "$GITHUB_WORKSPACE/../crane" copy "$source" "$local_image"
  source="$local_image"
fi

if [ -n "$summary_label" ]; then
  (
    echo "# $summary_label"
    echo
  ) >> "$GITHUB_STEP_SUMMARY"
fi

for destination in $destinations; do
  "$GITHUB_WORKSPACE/../crane" copy "$source" "$destination"
  echo "* [$destination](https://$destination)" >> "$GITHUB_STEP_SUMMARY"
done
