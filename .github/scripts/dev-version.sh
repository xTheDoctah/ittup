#!/usr/bin/env bash
# The dev version of HEAD: the patch after the last release plus the commits since it, e.g. 1.12.2.dev5.
# It sorts after the last release and before any next one, so pip never prefers it without --pre.
set -euo pipefail
last=$(git tag --list '[0-9]*.[0-9]*.[0-9]*' --merged HEAD | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
if [ -z "$last" ]; then
  echo "::error::No release tag in the history: fetch with fetch-depth: 0" >&2
  exit 1
fi
IFS=. read -r major minor patch <<<"$last"
echo "${major}.${minor}.$((patch + 1)).dev$(git rev-list --count "${last}..HEAD")"
