# Releasing

This document describes how to cut a new release of `linear-release-action`.

## When to release

Cut a new release whenever `main` has changes that should be picked up by consumers — most commonly after the [`linear-release` CLI](https://github.com/linear/linear-release) ships a new version that the action should default to.

## Prerequisites

- You must be on the `main` branch with a clean working tree, up to date with `origin/main`
- The [GitHub CLI](https://cli.github.com) (`gh`) must be installed and authenticated

## Creating a release

Run the release script with the target version:

```bash
./scripts/release.sh <version>
```

For example:

```bash
./scripts/release.sh 0.10.0
```

The version must follow `MAJOR.MINOR.PATCH` format (e.g., `0.10.0`, `1.0.0`).

By default the script sets the `cli_version` default to match the action version. When the two have drifted — for example, an action-only release while the CLI stays behind — pass the CLI version explicitly:

```bash
./scripts/release.sh 0.14.4 --cli-version 0.14.1
```

## What happens

The release script (`scripts/release.sh`) and CI workflows handle the full process:

### 1. `./scripts/release.sh <version>` (local)

The script runs preflight checks and then:

1. Validates the version format
2. Checks that `gh` is installed and authenticated
3. Verifies the working tree is clean, you're on `main`, and it's up to date with `origin/main`
4. Ensures the `v<version>` tag and `release/<version>` branch don't already exist
5. Creates a `release/<version>` branch
6. Bumps the version in [`VERSION`](./VERSION), the `cli_version` default in [`action.yml`](./action.yml), and the inputs table in [`README.md`](./README.md)
7. Commits the change and pushes the branch
8. Opens a PR against `main` via `gh pr create`

### 2. PR review and merge

Review and merge the PR as usual. The PR contains the version bumps only.

### 3. Auto-tagging (CI)

When a PR from a `release/*` branch is merged into `main`, the [Auto-tag release workflow](./.github/workflows/auto-tag-release.yml) runs automatically:

1. Validates that the branch version matches the `VERSION` file on `main`
2. Creates and pushes the `v<version>` tag
3. Triggers the [Release workflow](./.github/workflows/release.yml)

### 4. Release workflow (CI)

The Release workflow then:

1. Validates the tag format
2. Force-updates the floating `v<major>` tag (e.g. `v0`) to the same commit so consumers using `linear/linear-release-action@v0` pick up the change automatically
3. Creates a GitHub Release with auto-generated notes from the merged PRs since the previous tag

## Notes

- Consumers reference this action as `linear/linear-release-action@v0` (the floating major tag), so the major-tag move is the load-bearing step. Without it, consumers stay on whichever commit the major tag previously pointed to.
- The source of truth for the action's version is [`VERSION`](./VERSION); the auto-tag workflow fails if the branch name and `VERSION` file disagree.
- The script bumps the `cli_version` default to match the action version unless you pass `--cli-version`. The auto-tag workflow validates the `VERSION` file, not `cli_version`, so the two are free to diverge.
