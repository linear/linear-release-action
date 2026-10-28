#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/linear-release-run-tests.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

cat >"${TEST_ROOT}/linear-release" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\0' "$@" >"$MOCK_ARGS_FILE"
if [[ -n "${MOCK_RESPONSE:-}" ]]; then
  printf '%s\n' "$MOCK_RESPONSE"
else
  printf '{"release":null}\n'
fi
EOF
chmod +x "${TEST_ROOT}/linear-release"

invoke_runner() {
  local command="$1"
  shift
  : >"${TEST_ROOT}/github-output"
  rm -f "${TEST_ROOT}/args"
  env -i \
    PATH="$PATH" \
    GITHUB_ACTION_PATH="$TEST_ROOT" \
    GITHUB_OUTPUT="${TEST_ROOT}/github-output" \
    LINEAR_ACCESS_KEY="test-access-key" \
    COMMAND="$command" \
    INPUT_NAME="Test release" \
    INPUT_VERSION="v1.2.3" \
    INPUT_STAGE="staging" \
    MOCK_ARGS_FILE="${TEST_ROOT}/args" \
    "$@" \
    bash "$REPO_ROOT/run.sh" >"${TEST_ROOT}/output.log" 2>&1 || {
      cat "${TEST_ROOT}/output.log" >&2
      return 1
    }
}

assert_args() {
  # NUL separators preserve argument boundaries, embedded newlines, and trailing whitespace.
  printf '%s\0' "$@" >"${TEST_ROOT}/expected-args"
  if ! cmp "${TEST_ROOT}/expected-args" "${TEST_ROOT}/args"; then
    echo "CLI arguments did not match" >&2
    cat "${TEST_ROOT}/output.log" >&2
    return 1
  fi
}

descriptions=(
  'Release highlights'
  $'Release highlights:\n\n- First item\n- Second item\n'
  $'  "quotes" and \'apostrophes\'; $HOME $(exit 97) `exit 98` & | < > * ? [a-z] \\ path=value  '
  '--leading-dashes'
  $' \t\n'
)

for command in sync complete update; do
  for description in "${descriptions[@]}"; do
    invoke_runner "$command" "INPUT_DESCRIPTION=$description"
    assert_args "$command" --json "--name=Test release" "--description=$description" \
      --release-version=v1.2.3 --stage=staging
  done
  echo "ok - $command forwards descriptions verbatim as one argument"

  invoke_runner "$command" INPUT_DESCRIPTION=
  assert_args "$command" --json "--name=Test release" --release-version=v1.2.3 --stage=staging
  echo "ok - $command omits an empty description"

  invoke_runner "$command"
  assert_args "$command" --json "--name=Test release" --release-version=v1.2.3 --stage=staging
  echo "ok - $command omits an unset description"
done

# Compare the entire output file with the expected framing and original values.
# This rejects extra directives, duplicate outputs, and altered multiline data.
assert_outputs() {
  local field header delimiter
  : >"${TEST_ROOT}/expected-output"
  for field in id name version url; do
    header=$(sed -n "/^release-$field<<eof-/p" "${TEST_ROOT}/github-output")
    delimiter="${header#*<<}"
    [[ "$header" == "release-$field<<eof-"* && "$header" != *$'\n'* ]]
    {
      printf '%s\n' "$header"
      jq -j --arg field "$field" '.release[$field] // empty' <<<"$response"
      printf '\n%s\n' "$delimiter"
    } >>"${TEST_ROOT}/expected-output"
  done
  cmp "${TEST_ROOT}/expected-output" "${TEST_ROOT}/github-output"
}

for payload in '' 'Normal release' \
  $'release\nEOF\nrelease-id=forged\nextra-output=injected\n' \
  $'release\r\nEOF\r\nrelease-id<<EOF\r\nforged\r\nEOF\r\n' \
  $'quotes " \\ $(exit 97)\n\n'; do
  response=$(jq -n --arg value "$payload" \
    '{release: {id: $value, name: $value, version: $value, url: $value}}')
  invoke_runner sync "MOCK_RESPONSE=$response"
  assert_outputs
done
response='{"release":null}'
invoke_runner sync "MOCK_RESPONSE=$response"
assert_outputs
echo 'ok - outputs preserve empty and multiline values without injected directives'

# Force the first random delimiter to collide, then allow a fresh one.
mkdir -p "${TEST_ROOT}/bin"
cat >"${TEST_ROOT}/bin/od" <<'EOF'
#!/usr/bin/env bash
if [[ ! -e "$MOCK_OD_CALLED" ]]; then
  touch "$MOCK_OD_CALLED"
  printf '00000000000000000000000000000000\n'
else
  printf '11111111111111111111111111111111\n'
fi
EOF
chmod +x "${TEST_ROOT}/bin/od"
response=$(jq -n --arg value $'eof-00000000000000000000000000000000\r\nrelease-id=forged' \
  '{release: {id: $value, name: "Original name", version: "v1", url: "https://linear.app"}}')
invoke_runner sync "MOCK_RESPONSE=$response" "PATH=${TEST_ROOT}/bin:$PATH" \
  "MOCK_OD_CALLED=${TEST_ROOT}/od-called"
assert_outputs
echo 'ok - colliding delimiters are regenerated'
