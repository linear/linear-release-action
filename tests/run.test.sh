#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/linear-release-run-tests.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

cat >"${TEST_ROOT}/linear-release" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\0' "$@" >"$MOCK_ARGS_FILE"
printf '{"release":null}\n'
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
