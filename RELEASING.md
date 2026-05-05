# Releasing

This document describes how to cut a new release of `linear-release-action`.

## When to release

Cut a new release whenever `main` has changes that should be picked up by consumers — most commonly after bumping the default `cli_version` in [`action.yml`](./action.yml) to track a new [`linear-release` CLI](https://github.com/linear/linear-release) release.

## How to release

From a clean `main` checkout that's up to date with `origin/main`, push a `vMAJOR.MINOR.PATCH` tag:

```bash
git checkout main && git pull
git tag v0.7.2
git push origin v0.7.2
```

That triggers the [Release workflow](./.github/workflows/release.yml), which:

1. Validates the tag format.
2. Force-updates the floating `v<major>` tag (e.g. `v0`) to the same commit so consumers using `linear/linear-release-action@v0` pick up the change automatically.
3. Creates a GitHub Release with auto-generated notes from the merged PRs since the previous tag.

## Notes

- Consumers reference this action as `linear/linear-release-action@v0` (the floating major tag), so the major-tag move in step 2 is the load-bearing step. Without it, consumers stay on whichever commit the major tag previously pointed to.
- The action has no version-bearing file in the repo — the source of truth for the action's version is the git tag itself.
- The CLI version that the action installs at runtime is controlled by [`action.yml`'s `cli_version` default](./action.yml). To bump it, open a regular PR updating `action.yml` and `README.md`, merge, then cut a new action release with the steps above.
