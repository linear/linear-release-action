#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"

# --- Usage ---
if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 0.10.0"
  exit 1
fi

# --- Validate version format ---
if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "Error: Invalid version format '$VERSION'. Expected MAJOR.MINOR.PATCH (e.g., 0.10.0)"
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
git fetch origin main --tags --quiet
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

# --- Create release branch and bump versions ---
echo "Creating branch '$BRANCH'..."
git checkout -b "$BRANCH"

echo "Updating VERSION to $VERSION..."
echo "$VERSION" > VERSION

echo "Updating cli_version default in action.yml..."
sed -i.bak -E "s/^(    default: v)[0-9]+\.[0-9]+\.[0-9]+\$/\1$VERSION/" action.yml
sed -i.bak -E "s/(Linear Release CLI version to install \(e\.g\., \"v)[0-9]+\.[0-9]+\.[0-9]+(\"\))/\1$VERSION\2/" action.yml
rm action.yml.bak

echo "Updating cli_version reference in README.md..."
sed -i.bak -E "s/(\`v)[0-9]+\.[0-9]+\.[0-9]+(\` \| Linear Release CLI)/\1$VERSION\2/" README.md
rm README.md.bak

git add VERSION action.yml README.md
git commit -m "Release v$VERSION"

# --- Push and create PR ---
echo "Pushing branch..."
git push -u origin "$BRANCH"

echo "Creating pull request..."
PR_URL=$(gh pr create \
  --title "Release v$VERSION" \
  --body "Bumps the action and default CLI version to v$VERSION.

After this PR is merged, the \`v$VERSION\` tag will be created automatically, triggering the [Release workflow](./.github/workflows/release.yml)." \
  --base main)

echo ""
echo "PR created: $PR_URL"
echo "Once merged, the tag 'v$VERSION' will be created automatically and the release workflow will run."
