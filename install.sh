#!/usr/bin/env bash
set -euo pipefail

CLI_VERSION="${CLI_VERSION:-latest}"
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION_PATH="${GITHUB_ACTION_PATH:-$(pwd)}"
BIN_PATH="${ACTION_PATH}/linear-release"
LEGACY_VERSIONS_PATH="${SCRIPT_PATH}/legacy-versions.txt"
RELEASES_API="https://api.github.com/repos/linear/linear-release/releases"

error() {
  echo "::error::$*" >&2
}

is_legacy_version() {
  grep -Fqx -- "$1" "$LEGACY_VERSIONS_PATH"
}

fetch_release() {
  local endpoint="$1"
  local api_curl_args=(
    -fsSL
    -H "Accept: application/vnd.github+json"
    -H "X-GitHub-Api-Version: 2026-03-10"
  )
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    api_curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi
  curl "${api_curl_args[@]}" "${RELEASES_API}/${endpoint}"
}

release_asset_url() {
  local release_json="$1"
  local asset_name="$2"
  local count
  count=$(jq --arg name "$asset_name" '[.assets[] | select(.name == $name and .state == "uploaded")] | length' <<<"$release_json")
  if [[ "$count" -ne 1 ]]; then
    error "Expected exactly one '$asset_name' asset, found $count."
    return 1
  fi
  jq -r --arg name "$asset_name" '.assets[] | select(.name == $name and .state == "uploaded") | .browser_download_url' <<<"$release_json"
}

sha256() {
  local file="$1"
  if command -v sha256sum &>/dev/null; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum &>/dev/null; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    error "SHA-256 verification requires sha256sum or shasum."
    return 1
  fi
}

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
    error "Unsupported OS: ${RUNNER_OS:-unknown}"
    exit 1
    ;;
esac

if [[ ! -f "$LEGACY_VERSIONS_PATH" ]]; then
  error "Legacy release metadata not found at $LEGACY_VERSIONS_PATH."
  exit 1
fi

RELEASE_JSON=""
RESOLVED_VERSION="$CLI_VERSION"
if [[ "$CLI_VERSION" == "latest" ]]; then
  if ! command -v jq &>/dev/null; then
    error "jq is required to resolve and verify the latest CLI release."
    exit 1
  fi
  RELEASE_JSON=$(fetch_release "latest")
  RESOLVED_VERSION=$(jq -er '.tag_name | select(type == "string" and length > 0)' <<<"$RELEASE_JSON")
  echo "Resolved latest Linear Release CLI to $RESOLVED_VERSION"
fi

VERIFY_RELEASE=false
if ! is_legacy_version "$RESOLVED_VERSION"; then
  VERIFY_RELEASE=true
  if ! command -v jq &>/dev/null; then
    error "jq is required to verify CLI release $RESOLVED_VERSION."
    exit 1
  fi

  if [[ -z "$RELEASE_JSON" ]]; then
    ENCODED_VERSION=$(jq -rn --arg version "$RESOLVED_VERSION" '$version | @uri')
    RELEASE_JSON=$(fetch_release "tags/${ENCODED_VERSION}")
  fi

  RELEASE_TAG=$(jq -er '.tag_name | select(type == "string" and length > 0)' <<<"$RELEASE_JSON")
  if [[ "$RELEASE_TAG" != "$RESOLVED_VERSION" ]]; then
    error "Release metadata returned tag '$RELEASE_TAG', expected '$RESOLVED_VERSION'."
    exit 1
  fi
  if [[ "$(jq -r '.immutable' <<<"$RELEASE_JSON")" != "true" ]]; then
    error "CLI release $RESOLVED_VERSION is not immutable. Refusing to execute its assets."
    exit 1
  fi

  URL=$(release_asset_url "$RELEASE_JSON" "$ASSET")
  CHECKSUMS_URL=$(release_asset_url "$RELEASE_JSON" "checksums.txt")
else
  URL="https://github.com/linear/linear-release/releases/download/$RESOLVED_VERSION/$ASSET"
  echo "::notice::CLI release $RESOLVED_VERSION predates artifact verification; continuing with the legacy installation path."
fi

echo "Downloading Linear Release CLI from $URL"

curl_args=(-fsSL)
# Authenticate when a token is set for a higher rate limit; curl drops the header on the cross-host redirect to the asset CDN, so it's only sent to github.com.
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

TEMP_ROOT="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
TEMP_DIR=$(mktemp -d "${TEMP_ROOT%/}/linear-release.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT
DOWNLOADED_BIN="${TEMP_DIR}/${ASSET}"

curl "${curl_args[@]}" "$URL" -o "$DOWNLOADED_BIN"

if [[ "$VERIFY_RELEASE" == "true" ]]; then
  CHECKSUMS_PATH="${TEMP_DIR}/checksums.txt"
  curl "${curl_args[@]}" "$CHECKSUMS_URL" -o "$CHECKSUMS_PATH"

  MATCH_COUNT=$(awk -v asset="$ASSET" '$2 == asset {count++} END {print count + 0}' "$CHECKSUMS_PATH")
  if [[ "$MATCH_COUNT" -ne 1 ]]; then
    error "Expected exactly one checksum for '$ASSET', found $MATCH_COUNT."
    exit 1
  fi

  EXPECTED_SHA256=$(awk -v asset="$ASSET" '$2 == asset {print $1}' "$CHECKSUMS_PATH")
  if [[ ! "$EXPECTED_SHA256" =~ ^[[:xdigit:]]{64}$ ]]; then
    error "Malformed SHA-256 checksum for '$ASSET'."
    exit 1
  fi
  EXPECTED_SHA256=$(tr '[:upper:]' '[:lower:]' <<<"$EXPECTED_SHA256")
  ACTUAL_SHA256=$(sha256 "$DOWNLOADED_BIN")
  if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
    error "SHA-256 checksum mismatch for '$ASSET'."
    exit 1
  fi
  echo "Verified SHA-256 checksum for $ASSET from immutable release $RESOLVED_VERSION"
fi

chmod +x "$DOWNLOADED_BIN"
mv -f "$DOWNLOADED_BIN" "$BIN_PATH"

echo "Linear Release CLI installed at $BIN_PATH"
