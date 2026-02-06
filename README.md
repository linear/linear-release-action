<p align="center">
  <a href="https://linear.app" target="_blank" rel="noopener noreferrer">
    <img width="64" src="https://raw.githubusercontent.com/linear/linear/master/docs/logo.svg" alt="Linear logo">
  </a>
</p>
<h1 align="center">
  Linear Release Action
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

> [!NOTE]
> This project is currently in beta and requires enrollment to use. If you're interested in trying it out or need assistance, please contact [Linear support](https://linear.app/contact) or your account manager. APIs and commands may change in future releases.

## Overview

This action wraps the [Linear Release CLI](https://github.com/linear/linear-release) to integrate your CI/CD pipeline with [Linear's release management](https://linear.app/docs/releases). It automatically scans commits for Linear issue identifiers, detects pull request references, and creates or updates releases in Linear.

## Quick Start

```yaml
permissions:
  contents: read

steps:
  - uses: actions/checkout@v4
    with:
      fetch-depth: 0 # Required for commit history

  - uses: linear/linear-release-action@v0.1.0
    with:
      access_key: ${{ secrets.LINEAR_ACCESS_KEY }}
```

## Inputs

| Input           | Required | Default  | Description                                                                |
| --------------- | -------- | -------- | -------------------------------------------------------------------------- |
| `access_key`    | Yes      |          | Linear pipeline access key for authentication                              |
| `command`       | No       | `sync`   | Command to run: `sync`, `complete`, or `update`                            |
| `name`          | No       |          | Custom release name (only used with `sync` command)                        |
| `version`       | No       |          | Release version identifier                                                 |
| `stage`         | No       |          | Deployment stage such as `staging` or `production` (required for `update`) |
| `include_paths` | No       |          | Filter commits by file paths (comma-separated globs for monorepos)         |
| `cli_version`   | No       | `latest` | Linear Release CLI version tag to install                                  |

## Outputs

| Output            | Description                  |
| ----------------- | ---------------------------- |
| `release-id`      | The Linear release ID        |
| `release-name`    | The Linear release name      |
| `release-version` | The Linear release version   |
| `release-url`     | URL to the Linear release    |

Outputs are empty when no release is created (e.g. no matching commits found).

### Using outputs

```yaml
steps:
  - uses: actions/checkout@v4
    with:
      fetch-depth: 0

  - uses: linear/linear-release-action@v0.1.0
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
- uses: linear/linear-release-action@v0.1.0
  with:
    access_key: ${{ secrets.LINEAR_ACCESS_KEY }}
```

### complete

Marks the current release as complete. Only applicable to scheduled pipelines, as continuous pipelines create releases in the completed stage automatically.

```yaml
- uses: linear/linear-release-action@v0.1.0
  with:
    access_key: ${{ secrets.LINEAR_ACCESS_KEY }}
    command: complete
```

### update

Updates the deployment stage of the current release. Only applicable to scheduled pipelines, as continuous pipelines create releases in the completed stage automatically.

```yaml
- uses: linear/linear-release-action@v0.1.0
  with:
    access_key: ${{ secrets.LINEAR_ACCESS_KEY }}
    command: update
    stage: staging
```

### Monorepo filtering

Filter commits by file paths to track releases for specific packages:

```yaml
- uses: linear/linear-release-action@v0.1.0
  with:
    access_key: ${{ secrets.LINEAR_ACCESS_KEY }}
    include_paths: apps/web/**,packages/shared/**
```

## Troubleshooting

**"Unsupported OS" or "Unsupported arch" error**

The action only supports Linux x86_64 and macOS x86_64/arm64 runners. Windows is not supported.

**"access_key input is required" error**

Ensure you've set the `access_key` input with your Linear pipeline access key stored in GitHub Secrets.

**Issues not being linked**

Make sure your commits contain Linear issue identifiers (e.g., `ENG-123`) and that `actions/checkout` uses `fetch-depth: 0`.

## License

MIT - see [LICENSE](LICENSE)
