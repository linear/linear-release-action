#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <version> [--cli-version <version>]"
  echo "Example: $0 0.10.0"
  echo "Example: $0 0.14.4 --cli-version 0.14.1   # action and CLI versions drift"
}

validate_version() {
  echo "$1" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'
}

VERSION=""
CLI_VERSION=""

while [ $# -gt 0 ]; do
  case "$1" in
    --cli-version|--cli)
      if [ $# -lt 2 ]; then echo "Error: $1 requires a value"; usage; exit 1; fi
      CLI_VERSION="${2#v}"
      shift 2
      ;;
    --cli-version=*|--cli=*)
      CLI_VERSION="${1#*=}"
      CLI_VERSION="${CLI_VERSION#v}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Error: Unknown flag '$1'"
      usage
      exit 1
      ;;
    *)
      if [ -n "$VERSION" ]; then echo "Error: Unexpected argument '$1'"; usage; exit 1; fi
      VERSION="${1#v}"
      shift
      ;;
  esac
done

# --- Usage ---
if [ -z "$VERSION" ]; then
  usage
  exit 1
fi

# The CLI default tracks the action version unless an explicit drift is requested.
if [ -z "$CLI_VERSION" ]; then
  CLI_VERSION="$VERSION"
fi

# --- Validate version formats ---
if ! validate_version "$VERSION"; then
  echo "Error: Invalid version format '$VERSION'. Expected MAJOR.MINOR.PATCH (e.g., 0.10.0)"
  exit 1
fi
if ! validate_version "$CLI_VERSION"; then
  echo "Error: Invalid CLI version format '$CLI_VERSION'. Expected MAJOR.MINOR.PATCH (e.g., 0.10.0)"
  exit 1
fi

# --- Preflight checks ---

# gh CLI
if ! command -v gh &>/dev/null; then
  echo "Error: gh CLI is not installed. Install it from https://cli.github.com"
  exit 1
fi
if ! gh auth status &>/dev/null; then
  echo "Error: gh CLI is not authenticated. Run 'gh auth login' first."
  exit 1
fi

# Clean working tree
if [ -n "$(git status --porcelain)" ]; then
  echo "Error: Working tree is not clean. Commit or stash your changes first."
  exit 1
fi

# Must be on main
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "main" ]; then
  echo "Error: Must be on 'main' branch (currently on '$CURRENT_BRANCH')."
  exit 1
fi

# Up to date with origin/main
# --force keeps rolling tags (e.g. v0) in sync with the remote so they don't block the fetch.
git fetch origin main --tags --force
LOCAL_SHA=$(git rev-parse main)
REMOTE_SHA=$(git rev-parse origin/main)
if [ "$LOCAL_SHA" != "$REMOTE_SHA" ]; then
  echo "Error: Local 'main' is not up to date with 'origin/main'. Run 'git pull' first."
  exit 1
fi

# Tag must not exist
if git tag -l "v$VERSION" | grep -q .; then
  echo "Error: Tag 'v$VERSION' already exists."
  exit 1
fi

# Branch must not exist (local or remote)
BRANCH="release/$VERSION"
if git show-ref --verify --quiet "refs/heads/$BRANCH" 2>/dev/null; then
  echo "Error: Local branch '$BRANCH' already exists."
  exit 1
fi
if git ls-remote --exit-code --heads origin "$BRANCH" &>/dev/null; then
  echo "Error: Remote branch '$BRANCH' already exists."
  exit 1
fi

# --- Pin CLI checksums ---
CHECKSUMS_FILE="cli-checksums.txt"
CLI_ASSETS=(linear-release-linux-x64 linear-release-linux-arm64 linear-release-darwin-arm64 linear-release-darwin-x64)

pin_cli_checksums() {
  local tag="v$CLI_VERSION"
  if grep -q "^$tag " "$CHECKSUMS_FILE"; then
    echo "Checksums for CLI $tag already pinned."
    return
  fi

  echo "Pinning checksums for CLI $tag..."
  local immutable
  immutable=$(gh api "repos/linear/linear-release/releases/tags/$tag" --jq '.immutable')
  if [ "$immutable" != "true" ]; then
    echo "Error: CLI release $tag is not immutable."
    exit 1
  fi

  local checksums asset matches hash lines=""
  checksums=$(gh release download -R linear/linear-release "$tag" -p checksums.txt -O -)
  for asset in "${CLI_ASSETS[@]}"; do
    matches=$(awk -v asset="$asset" '$2 == asset {print $1}' <<<"$checksums")
    hash=$(tr '[:upper:]' '[:lower:]' <<<"$matches")
    if [ "$(grep -c . <<<"$hash")" -ne 1 ] || ! echo "$hash" | grep -qE '^[0-9a-f]{64}$'; then
      echo "Error: Expected exactly one SHA-256 entry for '$asset' in $tag checksums.txt."
      exit 1
    fi
    lines+="$tag $hash $asset"$'\n'
  done
  printf '%s' "$lines" >> "$CHECKSUMS_FILE"
}

pin_cli_checksums

# --- Create release branch and bump versions ---
echo "Creating branch '$BRANCH'..."
git checkout -b "$BRANCH"

echo "Updating VERSION to $VERSION..."
echo "$VERSION" > VERSION

PREV_CLI_VERSION=$(grep -E '^    default: v[0-9]+\.[0-9]+\.[0-9]+$' action.yml | sed -E 's/.*default: v//')

echo "Updating cli_version default in action.yml to v$CLI_VERSION..."
sed -i.bak -E "s/^(    default: v)[0-9]+\.[0-9]+\.[0-9]+\$/\1$CLI_VERSION/" action.yml
sed -i.bak -E "s/(Linear Release CLI version to install \(e\.g\., \"v)[0-9]+\.[0-9]+\.[0-9]+(\"\))/\1$CLI_VERSION\2/" action.yml
rm action.yml.bak

echo "Updating cli_version reference in README.md to v$CLI_VERSION..."
sed -i.bak -E "s/(\`v)[0-9]+\.[0-9]+\.[0-9]+(\` \| Linear Release CLI)/\1$CLI_VERSION\2/" README.md
rm README.md.bak

git add VERSION action.yml README.md "$CHECKSUMS_FILE"
git commit -m "Release v$VERSION"

# --- Push and create PR ---
echo "Pushing branch..."
git push -u origin "$BRANCH"

echo "Creating pull request..."
if [ "$CLI_VERSION" = "$VERSION" ]; then
  PR_BODY="Bumps the action and default CLI version to v$VERSION."
elif [ "$CLI_VERSION" = "$PREV_CLI_VERSION" ]; then
  PR_BODY="Bumps the action to v$VERSION (default CLI version stays at v$CLI_VERSION)."
else
  PR_BODY="Bumps the action to v$VERSION (default CLI version bumped to v$CLI_VERSION)."
fi
PR_URL=$(gh pr create \
  --title "Release v$VERSION" \
  --body "$PR_BODY

After this PR is merged, the \`v$VERSION\` tag will be created automatically, triggering the [Release workflow](./.github/workflows/release.yml)." \
  --base main)

echo ""
echo "PR created: $PR_URL"
echo "Once merged, the tag 'v$VERSION' will be created automatically and the release workflow will run."
