#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/linear-release-install-tests.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

MOCK_PATH="${REPO_ROOT}/tests/mocks"
REAL_CHMOD=$(command -v chmod)
chmod +x "$MOCK_PATH/curl" "$MOCK_PATH/chmod" "$MOCK_PATH/uname"

LAST_STATUS=0
CASE_DIR=""
OUTPUT_DIR=""
MOCK_RELEASE_JSON=""
MOCK_BINARY=""
MOCK_CHECKSUMS=""
MOCK_CURL_LOG=""
MOCK_CHMOD_LOG=""

sha256() {
  if command -v sha256sum &>/dev/null; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

new_case() {
  CASE_DIR="${TEST_ROOT}/$1"
  OUTPUT_DIR="${CASE_DIR}/action"
  MOCK_RELEASE_JSON="${CASE_DIR}/release.json"
  MOCK_BINARY="${CASE_DIR}/binary"
  MOCK_CHECKSUMS="${CASE_DIR}/checksums.txt"
  MOCK_CURL_LOG="${CASE_DIR}/curl.log"
  MOCK_CHMOD_LOG="${CASE_DIR}/chmod.log"
  mkdir -p "$OUTPUT_DIR"
  : >"$MOCK_CURL_LOG"
  : >"$MOCK_CHMOD_LOG"
}

write_release() {
  local tag="$1"
  local immutable="$2"
  local asset="$3"
  local include_checksums="$4"
  local checksum_asset=""
  if [[ "$include_checksums" == "true" ]]; then
    checksum_asset=',{"name":"checksums.txt","state":"uploaded","browser_download_url":"https://downloads.example/checksums.txt"}'
  fi
  printf '{"tag_name":"%s","immutable":%s,"assets":[{"name":"%s","state":"uploaded","browser_download_url":"https://downloads.example/%s"}%s]}\n' \
    "$tag" "$immutable" "$asset" "$asset" "$checksum_asset" >"$MOCK_RELEASE_JSON"
}

invoke_installer() {
  local version="$1"
  local runner_os="$2"
  local arch="$3"
  set +e
  env \
    PATH="${MOCK_PATH}:$PATH" \
    CLI_VERSION="$version" \
    GITHUB_ACTION_PATH="$OUTPUT_DIR" \
    RUNNER_OS="$runner_os" \
    RUNNER_TEMP="$CASE_DIR" \
    MOCK_ARCH="$arch" \
    MOCK_RELEASE_JSON="$MOCK_RELEASE_JSON" \
    MOCK_BINARY="$MOCK_BINARY" \
    MOCK_CHECKSUMS="$MOCK_CHECKSUMS" \
    MOCK_CURL_LOG="$MOCK_CURL_LOG" \
    MOCK_CHMOD_LOG="$MOCK_CHMOD_LOG" \
    REAL_CHMOD="$REAL_CHMOD" \
    bash "$REPO_ROOT/install.sh" >"${CASE_DIR}/output.log" 2>&1
  LAST_STATUS=$?
  set -e
}

assert_success() {
  if [[ "$LAST_STATUS" -ne 0 ]]; then
    command cat "${CASE_DIR}/output.log" >&2
    echo "Expected installer to succeed, got $LAST_STATUS" >&2
    return 1
  fi
}

assert_failure() {
  if [[ "$LAST_STATUS" -eq 0 ]]; then
    echo "Expected installer to fail" >&2
    return 1
  fi
}

assert_contains() {
  local file="$1"
  local expected="$2"
  if ! grep -Fq -- "$expected" "$file"; then
    echo "Expected $file to contain: $expected" >&2
    command cat "$file" >&2
    return 1
  fi
}

assert_not_installed() {
  if [[ -e "${OUTPUT_DIR}/linear-release" ]]; then
    echo "Binary was installed after verification failed" >&2
    return 1
  fi
  if [[ -s "$MOCK_CHMOD_LOG" ]]; then
    echo "chmod ran before verification succeeded" >&2
    return 1
  fi
}

test_legacy_release() {
  new_case "legacy-release"
  printf 'legacy-binary\n' >"$MOCK_BINARY"
  invoke_installer "v0.16.0" "Linux" "x86_64"
  assert_success
  assert_contains "$MOCK_CURL_LOG" "/v0.16.0/linear-release-linux-x64"
  cmp "$MOCK_BINARY" "${OUTPUT_DIR}/linear-release"
}

test_legacy_latest() {
  new_case "legacy-latest"
  printf 'legacy-binary\n' >"$MOCK_BINARY"
  : >"$MOCK_CHECKSUMS"
  write_release "v0.16.0" false "linear-release-linux-x64" false
  invoke_installer "latest" "Linux" "x86_64"
  assert_success
  assert_contains "$MOCK_CURL_LOG" "api.github.com"
  assert_contains "$MOCK_CURL_LOG" "/v0.16.0/linear-release-linux-x64"
}

test_verified_release() {
  new_case "verified-release"
  printf 'verified-binary\n' >"$MOCK_BINARY"
  write_release "v0.17.0" true "linear-release-linux-x64" true
  printf '%s  linear-release-linux-x64\n' "$(sha256 "$MOCK_BINARY")" >"$MOCK_CHECKSUMS"
  invoke_installer "v0.17.0" "Linux" "x86_64"
  assert_success
  assert_contains "${CASE_DIR}/output.log" "Verified SHA-256 checksum"
  cmp "$MOCK_BINARY" "${OUTPUT_DIR}/linear-release"
  [[ -x "${OUTPUT_DIR}/linear-release" ]]
}

test_tampered_release() {
  new_case "tampered-release"
  printf 'tampered-binary\n' >"$MOCK_BINARY"
  write_release "v0.17.0" true "linear-release-linux-x64" true
  printf '%064d  linear-release-linux-x64\n' 0 >"$MOCK_CHECKSUMS"
  invoke_installer "v0.17.0" "Linux" "x86_64"
  assert_failure
  assert_contains "${CASE_DIR}/output.log" "checksum mismatch"
  assert_not_installed
}

test_invalid_metadata() {
  new_case "missing-checksum"
  printf 'verified-binary\n' >"$MOCK_BINARY"
  : >"$MOCK_CHECKSUMS"
  write_release "v0.17.0" true "linear-release-linux-x64" false
  invoke_installer "v0.17.0" "Linux" "x86_64"
  assert_failure
  assert_contains "${CASE_DIR}/output.log" "checksums.txt"
  assert_not_installed

  new_case "mutable-release"
  printf 'verified-binary\n' >"$MOCK_BINARY"
  : >"$MOCK_CHECKSUMS"
  write_release "v0.17.0" false "linear-release-linux-x64" true
  invoke_installer "v0.17.0" "Linux" "x86_64"
  assert_failure
  assert_contains "${CASE_DIR}/output.log" "is not immutable"
  assert_not_installed
}

test_unsupported_platform() {
  new_case "unsupported-platform"
  printf 'binary\n' >"$MOCK_BINARY"
  : >"$MOCK_RELEASE_JSON"
  : >"$MOCK_CHECKSUMS"
  invoke_installer "v0.16.0" "Windows" "x86_64"
  assert_failure
  assert_contains "${CASE_DIR}/output.log" "Unsupported OS"
  if [[ -s "$MOCK_CURL_LOG" ]]; then
    echo "Network request occurred for an unsupported platform" >&2
    return 1
  fi
}

tests=(
  test_legacy_release
  test_legacy_latest
  test_verified_release
  test_tampered_release
  test_invalid_metadata
  test_unsupported_platform
)

for test_name in "${tests[@]}"; do
  "$test_name"
  echo "ok - $test_name"
done
