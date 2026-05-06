<p align="center">
  <a href="https://linear.app" target="_blank" rel="noopener noreferrer">
    <img width="64" src="https://raw.githubusercontent.com/linear/linear/master/docs/logo.svg" alt="Linear logo">
  </a>
</p>
<h1 align="center">
  @linear/release-action
</h1>
<h3 align="center">
  GitHub Action for syncing deployments with Linear releases
</h3>
<p align="center">
  Connect your deployments to Linear releases.<br/>
  Automatically link issues to releases.
</p>
<p align="center">
  <a href="https://github.com/linear/linear-release-action/actions/workflows/ci.yml"><img src="https://github.com/linear/linear-release-action/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/linear/linear-release-action/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="Linear Release Action is released under the MIT license."></a>
</p>

## Overview

This action wraps the [Linear Release CLI](https://github.com/linear/linear-release) to integrate your CI/CD pipeline with [Linear's release management](https://linear.app/docs/releases). It automatically scans commits for Linear issue identifiers, detects pull request references, and creates or updates releases in Linear.

For full documentation on pipeline types, how commit scanning works, path filtering details, and troubleshooting, see the [Linear Release CLI README](https://github.com/linear/linear-release#readme). This README covers the GitHub Action-specific configuration.

## Quick Start

```yaml
permissions:
  contents: read

steps:
  - uses: actions/checkout@v4
    with:
      fetch-depth: 0 # Required for commit history

  - uses: linear/linear-release-action@v0
    with:
      access_key: ${{ secrets.LINEAR_ACCESS_KEY }}
```

### AI-assisted setup

Use the Linear Release setup skill to generate CI configuration tailored to your project. It walks you through continuous vs. scheduled pipelines, monorepo path filtering, and more.

Copy the [SKILL.md](https://github.com/linear/linear-release/blob/main/skills/linear-release-setup/SKILL.md) into your project, or install it with [skills.sh](https://skills.sh):

```bash
npx skills add linear/linear-release
```

Once installed, run it from your AI agent with `/linear-release-setup` (or just ask the agent to set up Linear Release — it will pick up the skill automatically).

## Inputs

| Input           | Required | Default  | Description                                                                                                                                                                                                                   |
| --------------- | -------- | -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `access_key`    | Yes      |          | Linear pipeline access key for authentication                                                                                                                                                                                 |
| `command`       | No       | `sync`   | Command to run: `sync`, `complete`, or `update`                                                                                                                                                                               |
| `name`          | No       |          | Custom release name. For `sync`, the value is applied to the targeted release — both newly created releases and existing ones get the provided name. For `complete` and `update`, sets the name on the targeted release.                                          |
| `version`       | No       |          | Release version identifier (alias: `release_version`)                                                                                                                                                                         |
| `stage`         | No       |          | Deployment stage such as `staging` or `production` (required for `update`)                                                                                                                                                    |
| `include_paths` | No       |          | Filter commits by file paths (comma-separated globs for monorepos)                                                                                                                                                            |
| `log_level`     | No       |          | Log verbosity: `quiet` or `verbose`. Omit for default output.                                                                                                                                                                 |
| `timeout`       | No       | `60`     | Maximum time in seconds to wait for the command to complete                                                                                                                                                                   |
| `cli_version`   | No       | `v0.7.1` | Linear Release CLI version to install                                                                                                                                                                                         |

## Outputs

| Output            | Description                |
| ----------------- | -------------------------- |
| `release-id`      | The Linear release ID      |
| `release-name`    | The Linear release name    |
| `release-version` | The Linear release version |
| `release-url`     | URL to the Linear release  |

Outputs are empty when no release is created (e.g. no matching commits found).

### Using outputs

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      fetch-depth: 0

  - uses: linear/linear-release-action@v0
    id: release
    with:
      access_key: ${{ secrets.LINEAR_ACCESS_KEY }}

  - name: Use release outputs
    if: steps.release.outputs.release-url
    run: echo "Release URL is ${{ steps.release.outputs.release-url }}"
```

## Commands

### sync

Creates or updates a release by scanning commits for Linear issue identifiers.

```yaml
- uses: linear/linear-release-action@v0
  with:
    access_key: ${{ secrets.LINEAR_ACCESS_KEY }}
```

### complete

Marks the current release as complete. Only applicable to scheduled pipelines, as continuous pipelines create releases in the completed stage automatically.

```yaml
- uses: linear/linear-release-action@v0
  with:
    access_key: ${{ secrets.LINEAR_ACCESS_KEY }}
    command: complete
```

### update

Updates the deployment stage of the current release. Only applicable to scheduled pipelines, as continuous pipelines create releases in the completed stage automatically.

```yaml
- uses: linear/linear-release-action@v0
  with:
    access_key: ${{ secrets.LINEAR_ACCESS_KEY }}
    command: update
    stage: staging
```

### Command targeting

| Command    | With `version`                                   | Without `version`                                                                                                        |
| ---------- | ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------ |
| `sync`     | Targets matching version or creates that version | Continuous pipelines create a release with short SHA name/version. Scheduled pipelines use current started/planned flow. |
| `update`   | Updates that exact release version               | Updates latest started release, or latest planned release if no started release exists                                   |
| `complete` | Completes that exact release version             | Completes latest started release                                                                                         |

For scheduled pipelines, prefer always passing `version` in CI, especially when releases overlap.

### Path filtering

Filter commits by file paths to track releases for specific packages, useful for monorepos:

```yaml
- uses: linear/linear-release-action@v0
  with:
    access_key: ${{ secrets.LINEAR_ACCESS_KEY }}
    include_paths: apps/web/**,packages/shared/**
```

## Versioning

Each release of this action defaults to a specific [Linear Release CLI](https://github.com/linear/linear-release) version. Pinning the action — whether by tag (`@v0`) or commit SHA — also pins the CLI. Set `cli_version` to override.

## Troubleshooting

**"Unsupported OS" or "Unsupported arch" error**

The action only supports Linux x86_64 and macOS x86_64/arm64 runners. Windows is not supported.

**"access_key input is required" error**

Ensure you've set the `access_key` input with your Linear pipeline access key stored in GitHub Secrets.

**Issues not being linked**

Make sure your commits contain Linear issue identifiers (e.g., `ENG-123`) and that `actions/checkout` uses `fetch-depth: 0`.

**`name` is ignored on non-sync commands**

If `name` is provided with `command: update` or `command: complete`, the action prints a warning and continues. Use `name` with `command: sync` only.

## License

MIT - see [LICENSE](LICENSE)
