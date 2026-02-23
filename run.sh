#!/usr/bin/env bash
set -euo pipefail

ACTION_PATH="${GITHUB_ACTION_PATH:-$(pwd)}"
BIN_PATH="${ACTION_PATH}/linear-release"

if [[ -z "${LINEAR_ACCESS_KEY:-}" ]]; then
  echo "::error::access_key input is required"
  exit 1
fi

if [[ ! -x "$BIN_PATH" ]]; then
  echo "::error::Linear Release CLI not found at $BIN_PATH. Ensure the install step ran."
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "::error::jq is required but not found. Install jq or use a GitHub-hosted runner."
  exit 1
fi

if [[ -z "${GITHUB_OUTPUT:-}" ]]; then
  echo "::error::GITHUB_OUTPUT is not set. This action must run inside GitHub Actions."
  exit 1
fi

COMMAND="${COMMAND:-sync}"
case "$COMMAND" in
  sync|complete|update)
    ;;
  *)
    echo "::error::Invalid command '$COMMAND'. Must be: sync, complete, or update"
    exit 1
    ;;
esac

if [[ "$COMMAND" == "update" && -z "${INPUT_STAGE:-}" ]]; then
  echo "::error::stage input is required when command is 'update'"
  exit 1
fi

if [[ "$COMMAND" != "sync" && -n "${INPUT_NAME:-}" ]]; then
  echo "::warning::name input is ignored when command is '$COMMAND' (only used with 'sync')"
fi

args=()
[[ -n "${INPUT_NAME:-}" ]] && args+=("--name=${INPUT_NAME}")
[[ -n "${INPUT_VERSION:-}" ]] && args+=("--release-version=${INPUT_VERSION}")
[[ -n "${INPUT_STAGE:-}" ]] && args+=("--stage=${INPUT_STAGE}")
[[ -n "${INPUT_INCLUDE_PATHS:-}" ]] && args+=("--include-paths=${INPUT_INCLUDE_PATHS}")

echo "Running: $BIN_PATH $COMMAND ${args[*]}"

output=$("$BIN_PATH" "$COMMAND" --json "${args[@]}")

# Print the raw JSON so it appears in workflow logs
echo "$output"

# Validate output is valid JSON before parsing
if ! jq -e . >/dev/null 2>&1 <<<"$output"; then
  echo "::error::Linear Release CLI did not return valid JSON"
  exit 1
fi

# Parse and write outputs
{
  echo "release-id<<EOF"
  jq -r '.release.id // empty' <<<"$output"
  echo "EOF"
  echo "release-name<<EOF"
  jq -r '.release.name // empty' <<<"$output"
  echo "EOF"
  echo "release-version<<EOF"
  jq -r '.release.version // empty' <<<"$output"
  echo "EOF"
  echo "release-url<<EOF"
  jq -r '.release.url // empty' <<<"$output"
  echo "EOF"
} >> "$GITHUB_OUTPUT"
