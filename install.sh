#!/usr/bin/env bash
set -euo pipefail

CLI_VERSION="${CLI_VERSION:-latest}"
ACTION_PATH="${GITHUB_ACTION_PATH:-$(pwd)}"
BIN_PATH="${ACTION_PATH}/linear-release"

case "${RUNNER_OS:-}" in
  Linux)
    ARCH="$(uname -m)"
    if [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
      ASSET="linear-release-linux-x64"
    elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
      ASSET="linear-release-linux-arm64"
    else
      echo "::error::Unsupported Linux arch: $ARCH. Supported: x86_64, aarch64."
      exit 1
    fi
    ;;
  macOS)
    ARCH="$(uname -m)"
    if [[ "$ARCH" == "arm64" ]]; then
      ASSET="linear-release-darwin-arm64"
    elif [[ "$ARCH" == "x86_64" ]]; then
      ASSET="linear-release-darwin-x64"
    else
      echo "::error::Unsupported macOS arch: $ARCH. Only x86_64 and arm64 are supported."
      exit 1
    fi
    ;;
  *)
    echo "::error::Unsupported OS: ${RUNNER_OS:-unknown}"
    exit 1
    ;;
esac

if [[ "$CLI_VERSION" == "latest" ]]; then
  URL="https://github.com/linear/linear-release/releases/latest/download/$ASSET"
else
  URL="https://github.com/linear/linear-release/releases/download/$CLI_VERSION/$ASSET"
fi

echo "Downloading Linear Release CLI from $URL"

curl_args=(-fsSL)
# Authenticate when a token is set for a higher rate limit; curl drops the header on the cross-host redirect to the asset CDN, so it's only sent to github.com.
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

curl "${curl_args[@]}" "$URL" -o "$BIN_PATH"
chmod +x "$BIN_PATH"

echo "Linear Release CLI installed at $BIN_PATH"
