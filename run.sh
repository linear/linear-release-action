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

args=()
[[ -n "${INPUT_NAME:-}" ]] && args+=("--name=${INPUT_NAME}")
[[ -n "${INPUT_VERSION:-}" ]] && args+=("--version=${INPUT_VERSION}")
[[ -n "${INPUT_STAGE:-}" ]] && args+=("--stage=${INPUT_STAGE}")
[[ -n "${INPUT_INCLUDE_PATHS:-}" ]] && args+=("--include-paths=${INPUT_INCLUDE_PATHS}")

echo "Running: $BIN_PATH $COMMAND ${args[*]:-}"
"$BIN_PATH" "$COMMAND" ${args[@]+"${args[@]}"}
