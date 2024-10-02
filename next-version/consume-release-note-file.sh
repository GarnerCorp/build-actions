#!/usr/bin/env bash
set -eu
file="$1"
(
  echo "### $(basename "$file")"
  cat "$file"
  echo
  echo
)
git rm -q -f "$file"
