#!/usr/bin/env bash
set -euo pipefail

CHECKSUMS_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/cli-checksums.txt"
status=0

while read -r tag; do
  if [[ "$(gh api "repos/linear/linear-release/releases/tags/$tag" --jq '.immutable' </dev/null)" != "true" ]]; then
    echo "::error::CLI release $tag is not immutable."
    status=1
    continue
  fi

  published=$(gh release download -R linear/linear-release "$tag" -p checksums.txt -O - </dev/null)
  tag_status=0
  while read -r _ hash asset; do
    expected=$(awk -v asset="$asset" '$2 == asset {print tolower($1)}' <<<"$published")
    if [[ "$hash" != "$expected" ]]; then
      echo "::error::Pinned checksum for $asset in $tag does not match the release's checksums.txt."
      tag_status=1
    fi
  done < <(awk -v tag="$tag" '$1 == tag' "$CHECKSUMS_FILE")
  if [[ "$tag_status" -eq 0 ]]; then
    echo "Verified pinned checksums for $tag"
  else
    status=1
  fi
done < <(awk '{print $1}' "$CHECKSUMS_FILE" | sort -u)

exit "$status"
